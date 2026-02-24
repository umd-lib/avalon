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
# Partial migration: If the MasterFile source file is missing from the
# local filesystem but Derivatives are present, the job uploads and updates
# the Derivatives while leaving the MasterFile record unchanged. This is
# logged as a "partial" migration in the audit trail.
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
    master_file_upload = upload_master_file(master_file)
    derivative_uploads = upload_derivatives(master_file)

    # Mark as failed if derivative uploads contains nil entries
    if derivative_uploads.any?(&:nil?)
      Rails.logger.warn "[S3Migration] One or more derivatives for MasterFile #{master_file_id} failed to upload, aborting migration"
      return
    end

    masterfile_non_migrateable = master_file_upload.is_a?(Hash) && [:source_missing, :non_local].include?(master_file_upload[:status])
    if derivative_uploads.all? { |u| u[:status] == :already_migrated } && masterfile_non_migrateable
      Rails.logger.info "[S3Migration] All derivatives for MasterFile #{master_file_id} already migrated and masterfile non-migrateable, skipping"
      return
    end

    # Detect partial migration: MasterFile source missing but derivatives uploaded
    partial = masterfile_non_migrateable

    # Phase 2: Update Avalon records only after uploads succeeded
    save_master_file!(master_file, master_file_upload) unless partial
    save_derivatives!(derivative_uploads)

    # Phase 3: Write audit trail (single record for MasterFile + Derivatives)
    log_migration_audit(master_file, master_file_upload, derivative_uploads, partial: partial)

    if partial
      Rails.logger.warn "[S3Migration] Partial migration for MasterFile #{master_file_id}: source file missing, derivatives migrated"
    else
      Rails.logger.info "[S3Migration] Completed migration for MasterFile #{master_file_id}"
    end
  end

  private

    # ── Phase 1: Upload & Verify ────────────────────────────────────────

    # Uploads the MasterFile to S3 and verifies. Returns a hash with
    # upload details, or nil if the file was skipped.
    def upload_master_file(master_file)
      file_location = master_file.file_location

      if file_location.blank?
        Rails.logger.info "[S3Migration] MasterFile #{master_file.id} has blank file_location, skipping"
        return { status: :source_missing, source_path: nil }
      end

      # Only migrate local filesystem paths (not already S3, http, etc.)
      unless file_location.start_with?('/')
        Rails.logger.info "[S3Migration] MasterFile #{master_file.id} is not on local filesystem (#{truncate_path(file_location)}), skipping"
        return { status: :non_local, source_path: file_location }
      end

      unless File.exist?(file_location)
        Rails.logger.warn "[S3Migration] MasterFile #{master_file.id} source file not found: #{file_location}"
        return { status: :source_missing, source_path: file_location }
      end

      s3_uri    = masterfile_s3_uri(file_location)
      s3_object = FileLocator::S3File.new(s3_uri).object

      Rails.logger.info "[S3Migration] Uploading MasterFile #{master_file.id}: #{truncate_path(file_location)} -> #{truncate_path(s3_uri)}"
      s3_object.upload_file(file_location, checksum_algorithm: 'SHA256')

      # Verify
      raise "Upload verification failed for MasterFile #{master_file.id}" unless s3_object.exists?

      file_size = s3_object.content_length
      if master_file.file_size.present?
        expected = master_file.file_size.to_i
        raise "Size mismatch for MasterFile #{master_file.id}: expected #{expected}, got #{file_size}" unless expected == file_size
      end

      Rails.logger.info "[S3Migration] MasterFile #{master_file.id} uploaded and verified"
      { s3_uri: s3_uri, source_path: file_location, file_size: file_size }
    end

    # Uploads all Derivatives to S3 and verifies. Returns an array of
    # upload detail hashes for those that were uploaded.
    def upload_derivatives(master_file)
      results = []
      master_file.derivatives.each do |derivative|
        result = upload_derivative(derivative, master_file.id)
        results << result if result
      end
      results
    end

    # Uploads a single Derivative to S3 and verifies. Returns a hash
    # with upload details, or nil if skipped.
    def upload_derivative(derivative, master_file_id)
      deriv_location = derivative.derivativeFile

      if deriv_location.blank?
        Rails.logger.info "[S3Migration] Derivative #{derivative.id} has blank location, skipping"
        return nil
      end

      # If already in S3
      if deriv_location.start_with?('s3://')
        Rails.logger.info "[S3Migration] Derivative #{derivative.id} already in S3 (#{truncate_path(deriv_location)}), skipping"
        return { derivative: derivative, s3_uri: deriv_location, status: :already_migrated }
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

      file_size  = s3_object.content_length
      local_size = File.size(local_path)
      raise "Size mismatch for Derivative #{derivative.id}: expected #{local_size}, got #{file_size}" unless local_size == file_size

      Rails.logger.info "[S3Migration] Derivative #{derivative.id} uploaded and verified"
      { derivative: derivative, s3_uri: s3_uri, source_path: local_path, file_size: file_size }
    end

    # ── Phase 2: Update Avalon Records ──────────────────────────────────

    def save_master_file!(master_file, upload)
      return if upload.nil?

      master_file.file_location = upload[:s3_uri]
      master_file.save!
      Rails.logger.info "[S3Migration] MasterFile #{master_file.id} record updated to #{truncate_path(upload[:s3_uri])}"
    end

    def save_derivatives!(derivative_uploads)
      derivative_uploads.each do |entry|
        derivative = entry[:derivative]
        s3_uri     = entry[:s3_uri]

        # Setting absolute_location triggers set_streaming_locations! which
        # recalculates location_url and hls_url for the S3-based path
        derivative.absolute_location = s3_uri
        derivative.save!
        Rails.logger.info "[S3Migration] Derivative #{derivative.id} record updated to #{truncate_path(s3_uri)}"
      end
    end

    # ── Phase 3: Audit Trail ───────────────────────────────────────────

    # Write a single audit record containing the MasterFile and all its
    # Derivatives, keyed by the MasterFile ID.
    def log_migration_audit(master_file, master_file_upload, derivative_uploads, partial: false)
      media_object_id = master_file.media_object&.id

      mf_entry = nil
      if master_file_upload
        if [:source_missing, :non_local].include?(master_file_upload[:status])
          # Partial migration: record the missing source file
          mf_entry = {
            source_path:    master_file_upload[:source_path],
            destination_uri: nil,
            file_size:      nil,
            checksum:       nil,
            checksum_type:  nil,
            status:         'partial'
          }
        else
          mf_entry = {
            source_path:    master_file_upload[:source_path],
            destination_uri: master_file_upload[:s3_uri],
            file_size:      master_file_upload[:file_size],
            checksum:       fetch_s3_checksum(master_file_upload[:s3_uri]),
            checksum_type:  'SHA256'
          }
        end
      end

      deriv_entries = derivative_uploads.map do |entry|
        {
          resource_id:    entry[:derivative].id,
          source_path:    entry[:source_path],
          destination_uri: entry[:s3_uri],
          file_size:      entry[:file_size],
          checksum:       fetch_s3_checksum(entry[:s3_uri]),
          checksum_type:  'SHA256'
        }
      end

      S3MigrationLogger.log_master_file_migration(
        master_file_id:  master_file.id,
        media_object_id: media_object_id,
        master_file:     mf_entry,
        derivatives:     deriv_entries
      )
    rescue => e
      # Audit logging failure should not fail the migration itself
      Rails.logger.warn "[S3Migration] Failed to log audit entry for MasterFile #{master_file.id}: #{e.message}"
    end

    # Fetch the SHA-256 checksum stored on the S3 object after upload.
    # Returns nil if the checksum cannot be retrieved.
    def fetch_s3_checksum(s3_uri)
      s3_object = FileLocator::S3File.new(s3_uri).object
      resp = s3_object.client.head_object(
        bucket: s3_object.bucket_name,
        key:    s3_object.key,
        checksum_mode: 'ENABLED'
      )
      resp.checksum_sha256
    rescue => e
      Rails.logger.warn "[S3Migration] Could not fetch checksum for #{truncate_path(s3_uri)}: #{e.message}"
      nil
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
