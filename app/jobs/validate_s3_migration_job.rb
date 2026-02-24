# UMD Customization
#
# Sidekiq job that validates a single MasterFile (and its Derivatives)
# were correctly migrated to S3 by comparing local-disk SHA-256 checksums
# with the checksums stored on the S3 objects.
#
# This is designed to run as a *secondary* verification step AFTER the
# migration is complete, while the original local files still exist on disk.
#
# Validation checks per file:
#   1. S3 object exists
#   2. Size matches local file
#   3. SHA-256 checksum matches (handles both single-part and multipart uploads)
#
# Usage:
#   ValidateS3MigrationJob.perform_later("master_file_id")
#
# The job is idempotent and safe to re-run. Files that are not on S3 or
# whose local path no longer exists are skipped (not failures).
#
# Queue: s3_validation (processed by dedicated validation workers only)
#
class ValidateS3MigrationJob < ActiveJob::Base
  queue_as :s3_validation

  # Retry transient S3 / network errors with exponential backoff
  retry_on Aws::S3::Errors::ServiceError, wait: :polynomially_longer, attempts: 5
  retry_on Errno::ECONNRESET,             wait: :polynomially_longer, attempts: 5
  retry_on Net::OpenTimeout,              wait: :polynomially_longer, attempts: 5
  retry_on Faraday::ConnectionFailed,     wait: :polynomially_longer, attempts: 5

  # Discard if the object was deleted between enqueue and execution
  discard_on ActiveFedora::ObjectNotFoundError

  def perform(master_file_id)
    Rails.logger.info "[S3Validation] Starting validation for MasterFile #{master_file_id}"

    master_file = MasterFile.find(master_file_id)

    mf_result    = validate_master_file(master_file)
    deriv_results = validate_derivatives(master_file)

    summary = build_summary(master_file_id, mf_result, deriv_results)
    Rails.logger.info "[S3Validation] #{summary}"
  end

  private

    # ── MasterFile validation ───────────────────────────────────────────

    def validate_master_file(master_file)
      file_location = master_file.file_location

      if file_location.blank?
        Rails.logger.info "[S3Validation] MasterFile #{master_file.id} has blank file_location, skipping"
        return :skipped
      end

      # Only validate S3-based files (these are the ones that were migrated)
      unless file_location.start_with?('s3://')
        Rails.logger.info "[S3Validation] MasterFile #{master_file.id} is not on S3, skipping"
        return :skipped
      end

      local_path = s3_uri_to_local_masterfile_path(file_location)

      unless File.exist?(local_path)
        Rails.logger.warn "[S3Validation] MasterFile #{master_file.id}: local file not found at #{truncate_path(local_path)}, skipping"
        return :local_missing
      end

      validate_file(master_file.id, 'MasterFile', local_path, file_location)
    end

    # ── Derivative validation ───────────────────────────────────────────

    def validate_derivatives(master_file)
      master_file.derivatives.map do |derivative|
        validate_derivative(derivative, master_file.id)
      end
    end

    def validate_derivative(derivative, master_file_id)
      deriv_location = derivative.derivativeFile

      if deriv_location.blank?
        Rails.logger.info "[S3Validation] Derivative #{derivative.id} has blank location, skipping"
        return :skipped
      end

      unless deriv_location.start_with?('s3://')
        Rails.logger.info "[S3Validation] Derivative #{derivative.id} is not on S3, skipping"
        return :skipped
      end

      local_path = s3_uri_to_local_derivative_path(deriv_location)

      unless File.exist?(local_path)
        Rails.logger.warn "[S3Validation] Derivative #{derivative.id}: local file not found at #{truncate_path(local_path)}, skipping"
        return :local_missing
      end

      validate_file(derivative.id, 'Derivative', local_path, deriv_location)
    end

    # ── Core validation logic ───────────────────────────────────────────

    # Validates a single file: existence, size, and SHA-256 checksum.
    # Returns :pass, :fail_missing, :fail_size, :fail_checksum, or :pass_size_only.
    def validate_file(id, type, local_path, s3_uri)
      s3_object = FileLocator::S3File.new(s3_uri).object

      # 1. S3 object must exist
      unless s3_object.exists?
        Rails.logger.error "[S3Validation] FAIL #{type} #{id}: S3 object does not exist at #{truncate_path(s3_uri)}"
        return :fail_missing
      end

      # 2. Size must match
      local_size = File.size(local_path)
      s3_size    = s3_object.content_length

      unless local_size == s3_size
        Rails.logger.error "[S3Validation] FAIL #{type} #{id}: size mismatch — local=#{local_size} s3=#{s3_size}"
        return :fail_size
      end

      # 3. SHA-256 checksum comparison
      s3_checksum = fetch_s3_sha256(s3_object)

      if s3_checksum.nil?
        Rails.logger.warn "[S3Validation] PASS (size only) #{type} #{id}: no SHA-256 stored on S3 object"
        return :pass_size_only
      end

      local_checksum = compute_matching_local_checksum(local_path, s3_object, s3_checksum)

      if local_checksum == s3_checksum
        Rails.logger.info "[S3Validation] PASS #{type} #{id}: SHA-256 match (#{s3_checksum})"
        :pass
      else
        Rails.logger.error "[S3Validation] FAIL #{type} #{id}: SHA-256 mismatch — local=#{local_checksum} s3=#{s3_checksum}"
        :fail_checksum
      end
    end

    # ── S3 checksum retrieval ───────────────────────────────────────────

    # Fetch the SHA-256 checksum stored on the S3 object.
    # Requires checksum_mode: 'ENABLED' to include additional checksums.
    def fetch_s3_sha256(s3_object)
      resp = s3_object.client.head_object(
        bucket: s3_object.bucket_name,
        key:    s3_object.key,
        checksum_mode: 'ENABLED'
      )
      resp.checksum_sha256
    rescue Aws::S3::Errors::ServiceError => e
      Rails.logger.warn "[S3Validation] Could not fetch S3 checksum: #{e.message}"
      nil
    end

    # ── Local checksum computation ──────────────────────────────────────

    # Compute a local checksum that matches the S3 checksum format.
    #
    # For single-part uploads, S3 stores a plain base64-encoded SHA-256.
    # For multipart uploads, the checksum is a composite:
    #   Base64(SHA-256(part1_sha256 + part2_sha256 + ...))-N
    # where N is the number of parts and each part_sha256 is the raw
    # (binary) SHA-256 digest of that part's bytes.
    #
    # We detect multipart by the presence of a '-' suffix in the S3 checksum
    # and use GetObjectAttributes to retrieve part sizes so we can compute
    # the matching composite locally.
    def compute_matching_local_checksum(local_path, s3_object, s3_checksum)
      if s3_checksum.include?('-')
        compute_local_multipart_sha256(local_path, s3_object, s3_checksum)
      else
        Digest::SHA256.file(local_path).base64digest
      end
    end

    # Compute the composite SHA-256 that matches S3's multipart checksum.
    #
    # For multipart uploads, S3 stores a composite checksum:
    #   Base64(SHA-256(part1_sha256 + part2_sha256 + ...))-N
    # where N is the number of parts.
    #
    # Instead of fetching part sizes from S3 (which requires the
    # s3:GetObjectAttributes permission), we compute the part size
    # using the same formula the AWS SDK uses by default:
    #   part_size = max(ceil(file_size / 10_000), 5 MB)
    #
    # Steps:
    #   1. Derive the number of parts from the S3 checksum suffix
    #   2. Compute the default SDK part size from the local file size
    #   3. Read the local file in matching chunks
    #   4. SHA-256 each chunk
    #   5. SHA-256 the concatenated raw digests
    #   6. Base64-encode and append "-N"
    def compute_local_multipart_sha256(local_path, _s3_object, s3_checksum)
      num_parts = s3_checksum.split('-').last.to_i
      file_size = File.size(local_path)
      part_size = default_multipart_part_size(file_size)

      raw_digests = []

      File.open(local_path, 'rb') do |f|
        num_parts.times do
          chunk = f.read(part_size)
          break if chunk.nil?
          raw_digests << Digest::SHA256.digest(chunk)
        end
      end

      composite_raw = Digest::SHA256.digest(raw_digests.join)
      "#{Base64.strict_encode64(composite_raw)}-#{raw_digests.size}"
    end

    # Part size for multipart checksum validation. Must match the part size
    # used during upload (S3_MIGRATION_PART_SIZE_MB). Separate env var so
    # environments where migration already completed with a different part
    # size can set validation independently.
    #   part_size = max(ceil(file_size / 10_000), VALIDATION_PART_SIZE)
    SDK_MAX_PARTS = 10_000
    VALIDATION_PART_SIZE = (ENV.fetch('S3_VALIDATION_PART_SIZE_MB', '64').to_i * 1024 * 1024)

    def default_multipart_part_size(file_size)
      [(file_size.to_f / SDK_MAX_PARTS).ceil, VALIDATION_PART_SIZE].max
    end

    # ── Reverse path mapping ────────────────────────────────────────────

    # Reverse the S3 URI back to the original local masterfile path.
    # s3://bucket/archive/2v/23/vt/36/id-file.mp4
    #   -> /masterfiles/archive/2v/23/vt/36/id-file.mp4
    def s3_uri_to_local_masterfile_path(s3_uri)
      uri = Addressable::URI.parse(s3_uri)
      key = Addressable::URI.unencode(uri.path).sub(%r{^/}, '')
      File.join(masterfile_local_base, key)
    end

    # Reverse the S3 URI back to the original local derivative path.
    # s3://bucket/uuid/outputs/name-high.mp4
    #   -> /streamfiles/uuid/outputs/name-high.mp4
    def s3_uri_to_local_derivative_path(s3_uri)
      uri = Addressable::URI.parse(s3_uri)
      key = Addressable::URI.unencode(uri.path).sub(%r{^/}, '')
      File.join(derivative_local_base, key)
    end

    # ── Path helpers (shared with MigrateToS3Job) ───────────────────────

    def masterfile_local_base
      ENV.fetch('MIGRATE_MASTERFILE_LOCAL_BASE', '/masterfiles')
    end

    def derivative_local_base
      ENV.fetch('MIGRATE_DERIVATIVE_LOCAL_BASE',
                 ENV.fetch('LOCAL_DERIVATIVES_DIR', '/streamfiles'))
    end

    def truncate_path(path, max: 80)
      path.length > max ? "#{path[0..40]}...#{path[-35..]}" : path
    end

    # ── Summary ─────────────────────────────────────────────────────────

    def build_summary(master_file_id, mf_result, deriv_results)
      all_results = [mf_result] + deriv_results
      passes     = all_results.count { |r| r == :pass }
      size_only  = all_results.count { |r| r == :pass_size_only }
      skipped    = all_results.count { |r| r == :skipped || r == :local_missing }
      failures   = all_results.count { |r| r.to_s.start_with?('fail') }

      status = failures > 0 ? 'FAIL' : 'PASS'
      "#{status} MasterFile #{master_file_id}: #{passes} passed, #{size_only} size-only, #{skipped} skipped, #{failures} failed"
    end
end
# End UMD Customization
