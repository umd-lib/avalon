# UMD Customization
#
# Sidekiq job that migrates a single MasterFile and all its Derivatives
# from the local filesystem to S3.
#
# The job operates in two phases:
#   Phase 1 — Upload all files (MasterFile + Derivatives) to S3 with
#             SHA-256 checksum verification, confirming existence and size.
#   Phase 2 — Only after ALL uploads succeed, update the Avalon records
#             with their new S3 locations.
#
# This ensures that a partial upload failure never leaves records pointing
# at S3 objects that don't exist. On retry, already-uploaded objects will
# be re-uploaded (S3 overwrites are atomic) and then records are updated.
#
# Usage:
#   MigrateToS3Job.perform_later("master_file_id")
#
# The job is idempotent — re-running it for an already-migrated MasterFile
# is a safe no-op. This makes the migration resumable: simply re-enqueue
# all candidates and already-completed items will be skipped.
#
# Queue: s3_migration (processed by dedicated migration workers only)
#
class MigrateToS3Job < ActiveJob::Base
  queue_as :s3_migration

  # Retry transient S3 / network errors with exponential backoff
  retry_on Aws::S3::Errors::ServiceError, wait: :polynomially_longer, attempts: 5
  retry_on Errno::ECONNRESET,             wait: :polynomially_longer, attempts: 5
  retry_on Net::OpenTimeout,              wait: :polynomially_longer, attempts: 5
  retry_on Faraday::ConnectionFailed,     wait: :polynomially_longer, attempts: 5

  # Discard if the object was deleted between enqueue and execution
  discard_on ActiveFedora::ObjectNotFoundError

  def perform(master_file_id)
    Rails.logger.info "[S3Migration] Starting migration for MasterFile #{master_file_id}"

    master_file = MasterFile.find(master_file_id)

    # Phase 1: Upload all files to S3 and verify (no metadata changes yet)
    master_file_s3_uri = upload_master_file(master_file)
    derivative_s3_uris = upload_derivatives(master_file)

    # Phase 2: Update Avalon records only after ALL uploads succeeded
    save_master_file!(master_file, master_file_s3_uri)
    save_derivatives!(derivative_s3_uris)

    Rails.logger.info "[S3Migration] Completed migration for MasterFile #{master_file_id}"
  end

  private

    # ── Phase 1: Upload & Verify ────────────────────────────────────────

    # Uploads the MasterFile to S3 and verifies. Returns the S3 URI,
    # or nil if the file was skipped (already migrated, blank, etc.).
    def upload_master_file(master_file)
      file_location = master_file.file_location

      if file_location.blank?
        Rails.logger.info "[S3Migration] MasterFile #{master_file.id} has blank file_location, skipping"
        return nil
      end

      # Only migrate local filesystem paths (not already S3, http, etc.)
      unless file_location.start_with?('/')
        Rails.logger.info "[S3Migration] MasterFile #{master_file.id} is not on local filesystem (#{truncate_path(file_location)}), skipping"
        return nil
      end

      raise "Source file not found: #{file_location}" unless File.exist?(file_location)

      s3_uri    = masterfile_s3_uri(file_location)
      s3_object = FileLocator::S3File.new(s3_uri).object

      Rails.logger.info "[S3Migration] Uploading MasterFile #{master_file.id}: #{truncate_path(file_location)} -> #{truncate_path(s3_uri)}"
      s3_object.upload_file(file_location, checksum_algorithm: 'SHA256')

      # Verify
      raise "Upload verification failed for MasterFile #{master_file.id}" unless s3_object.exists?

      if master_file.file_size.present?
        expected = master_file.file_size.to_i
        actual   = s3_object.content_length
        raise "Size mismatch for MasterFile #{master_file.id}: expected #{expected}, got #{actual}" unless expected == actual
      end

      Rails.logger.info "[S3Migration] MasterFile #{master_file.id} uploaded and verified"
      s3_uri
    end

    # Uploads all Derivatives to S3 and verifies. Returns an array of
    # { derivative:, s3_uri: } hashes for those that were uploaded.
    def upload_derivatives(master_file)
      results = []
      master_file.derivatives.each do |derivative|
        s3_uri = upload_derivative(derivative, master_file.id)
        results << { derivative: derivative, s3_uri: s3_uri } if s3_uri
      end
      results
    end

    # Uploads a single Derivative to S3 and verifies. Returns the S3 URI,
    # or nil if skipped.
    def upload_derivative(derivative, master_file_id)
      deriv_location = derivative.derivativeFile

      if deriv_location.blank?
        Rails.logger.info "[S3Migration] Derivative #{derivative.id} has blank location, skipping"
        return nil
      end

      # Only migrate file:// derivatives (not already S3, http, etc.)
      unless deriv_location.start_with?('file://')
        Rails.logger.info "[S3Migration] Derivative #{derivative.id} is not file-based (#{truncate_path(deriv_location)}), skipping"
        return nil
      end

      # Skip unmanaged derivatives — Avalon doesn't control their lifecycle
      unless derivative.managed
        Rails.logger.warn "[S3Migration] Derivative #{derivative.id} is unmanaged, skipping"
        return nil
      end

      local_path = Addressable::URI.parse(deriv_location).path
      raise "Derivative source not found: #{local_path}" unless File.exist?(local_path)

      s3_uri    = derivative_s3_uri(local_path)
      s3_object = FileLocator::S3File.new(s3_uri).object

      Rails.logger.info "[S3Migration] Uploading Derivative #{derivative.id}: #{truncate_path(local_path)} -> #{truncate_path(s3_uri)}"
      s3_object.upload_file(local_path, checksum_algorithm: 'SHA256')

      # Verify
      raise "Upload verification failed for Derivative #{derivative.id}" unless s3_object.exists?

      local_size = File.size(local_path)
      actual     = s3_object.content_length
      raise "Size mismatch for Derivative #{derivative.id}: expected #{local_size}, got #{actual}" unless local_size == actual

      Rails.logger.info "[S3Migration] Derivative #{derivative.id} uploaded and verified"
      s3_uri
    end

    # ── Phase 2: Update Avalon Records ──────────────────────────────────

    def save_master_file!(master_file, s3_uri)
      return if s3_uri.nil?

      master_file.file_location = s3_uri
      master_file.save!
      Rails.logger.info "[S3Migration] MasterFile #{master_file.id} record updated to #{truncate_path(s3_uri)}"
    end

    def save_derivatives!(derivative_s3_uris)
      derivative_s3_uris.each do |entry|
        derivative = entry[:derivative]
        s3_uri     = entry[:s3_uri]

        # Setting absolute_location triggers set_streaming_locations! which
        # recalculates location_url and hls_url for the S3-based path
        derivative.absolute_location = s3_uri
        derivative.save!
        Rails.logger.info "[S3Migration] Derivative #{derivative.id} record updated to #{truncate_path(s3_uri)}"
      end
    end

    # ── Path helpers ────────────────────────────────────────────────────

    # Convert local masterfile path to S3 URI
    # e.g. /masterfiles/archive/2v/23/vt/36/id-file.mp4
    #   -> s3://bucket/archive/2v/23/vt/36/id-file.mp4
    def masterfile_s3_uri(file_location)
      base = masterfile_local_base
      relative_key = file_location.sub(%r{^#{Regexp.escape(base)}/?}, '')
      "s3://#{Settings.encoding.masterfile_bucket}/#{relative_key}"
    end

    # Convert local derivative path to S3 URI
    # e.g. /streamfiles/uuid/outputs/name-high.mp4
    #   -> s3://bucket/uuid/outputs/name-high.mp4
    def derivative_s3_uri(local_path)
      base = derivative_local_base
      relative_key = local_path.sub(%r{^#{Regexp.escape(base)}/?}, '')
      "s3://#{Settings.encoding.derivative_bucket}/#{relative_key}"
    end

    # The local filesystem root for archived master files.
    # In K8s the PVC is mounted at /masterfiles.
    def masterfile_local_base
      ENV.fetch('MIGRATE_MASTERFILE_LOCAL_BASE', '/masterfiles')
    end

    # The local filesystem root for derivative/streaming files.
    # In K8s the PVC is mounted at /streamfiles.
    def derivative_local_base
      ENV.fetch('MIGRATE_DERIVATIVE_LOCAL_BASE',
                 ENV.fetch('LOCAL_DERIVATIVES_DIR', '/streamfiles'))
    end

    def truncate_path(path, max: 80)
      path.length > max ? "#{path[0..40]}...#{path[-35..]}" : path
    end
end
# End UMD Customization
