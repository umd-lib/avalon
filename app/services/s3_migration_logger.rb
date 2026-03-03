# UMD Customization
#
# S3-based audit logger for S3 migration.
#
# Each MasterFile and its Derivatives are logged as a single S3 object
# containing multiple CSV rows (one for the MasterFile, one per Derivative),
# keyed by the MasterFile ID. ActiveStorage blobs are logged as separate
# individual objects.
#
# This avoids the need for a mounted volume and eliminates concurrency
# issues — each MasterFile job writes to its own unique S3 key, so
# multiple Sidekiq workers (even across pods) can write simultaneously.
#
# Entries are written to:
#   s3://<bucket>/<prefix>/MasterFile-<master_file_id>.csv
#   s3://<bucket>/<prefix>/ActiveStorage-blob-<blob_id>.csv
#
# The report rake task lists all objects under the prefix and merges them
# into a single CSV.
#
# Configuration (environment variables):
#   S3_MIGRATION_LOG_BUCKET  — S3 bucket (default: Settings.encoding.masterfile_bucket)
#   S3_MIGRATION_LOG_PREFIX  — Key prefix (default: migration-audit)
#
# Usage:
#   S3MigrationLogger.log_master_file_migration(
#     master_file_id:  "abc123",
#     media_object_id: "xyz789",
#     master_file:     { source_path: "/local/file.mp4", destination_uri: "s3://bucket/file.mp4", ... },
#     derivatives:     [{ resource_id: "def456", source_path: "...", destination_uri: "...", ... }]
#   )
#
#   S3MigrationLogger.log_migration(
#     resource_id: "blob-99", resource_type: "ActiveStorage", ...
#   )
#
class S3MigrationLogger
  HEADERS = %w[
    resource_id resource_type media_object_id master_file_id source_path destination_uri
    file_size checksum checksum_type status error_message migrated_at
  ].freeze

  class << self
    # Log a MasterFile and all its Derivatives as a single audit record.
    #
    # @param master_file_id  [String] The MasterFile ID (used as the S3 key)
    # @param media_object_id [String] The parent MediaObject ID
    # @param master_file     [Hash]   { source_path:, destination_uri:, file_size:, checksum:, checksum_type:, status: }
    #                                 or nil if the MasterFile was skipped.
    #                                 status defaults to 'migrated'. Use 'partial' when the source
    #                                 file is missing but derivatives were migrated.
    # @param derivatives     [Array<Hash>] each: { resource_id:, source_path:, destination_uri:, file_size:, checksum:, checksum_type: }
    def log_master_file_migration(master_file_id:, media_object_id:, master_file: nil, derivatives: [])
      rows = []
      now = Time.current.iso8601

      if master_file
        mf_status = master_file[:status] || 'migrated'
        error_msg = mf_status == 'partial' ? 'Source file missing on local filesystem' : nil

        rows << {
          resource_id:     master_file_id,
          resource_type:   'MasterFile',
          media_object_id: media_object_id,
          master_file_id:  master_file_id,
          source_path:     master_file[:source_path],
          destination_uri: master_file[:destination_uri],
          file_size:       master_file[:file_size],
          checksum:        master_file[:checksum],
          checksum_type:   master_file[:checksum_type] || 'SHA256',
          status:          mf_status,
          error_message:   error_msg,
          migrated_at:     now
        }
      end

      derivatives.each do |d|
        rows << {
          resource_id:     d[:resource_id],
          resource_type:   'Derivative',
          media_object_id: media_object_id,
          master_file_id:  master_file_id,
          source_path:     d[:source_path],
          destination_uri: d[:destination_uri],
          file_size:       d[:file_size],
          checksum:        d[:checksum],
          checksum_type:   d[:checksum_type] || 'SHA256',
          status:          'migrated',
          error_message:   nil,
          migrated_at:     now
        }
      end

      write_entry("MasterFile-#{sanitize_id(master_file_id)}", rows) unless rows.empty?
    end

    # Log a single resource migration (used for ActiveStorage blobs).
    def log_migration(resource_id:, resource_type:, source_path:, destination_uri:,
                      file_size: nil, checksum: nil, checksum_type: nil,
                      media_object_id: nil, master_file_id: nil)
      row = {
        resource_id:     resource_id,
        resource_type:   resource_type,
        media_object_id: media_object_id,
        master_file_id:  master_file_id,
        source_path:     source_path,
        destination_uri: destination_uri,
        file_size:       file_size,
        checksum:        checksum,
        checksum_type:   checksum_type,
        status:          'migrated',
        error_message:   nil,
        migrated_at:     Time.current.iso8601
      }
      write_entry("#{resource_type}-#{sanitize_id(resource_id)}", [row])
    end

    # Log a failed migration.
    def log_failure(resource_id:, resource_type:, source_path:, destination_uri:,
                    error_message:, media_object_id: nil, master_file_id: nil)
      row = {
        resource_id:     resource_id,
        resource_type:   resource_type,
        media_object_id: media_object_id,
        master_file_id:  master_file_id,
        source_path:     source_path,
        destination_uri: destination_uri,
        file_size:       nil,
        checksum:        nil,
        checksum_type:   nil,
        status:          'failed',
        error_message:   error_message,
        migrated_at:     Time.current.iso8601
      }
      write_entry("#{resource_type}-#{sanitize_id(resource_id)}", [row])
    end

    # S3 bucket for audit log entries.
    def log_bucket
      ENV.fetch('S3_MIGRATION_LOG_BUCKET', Settings.encoding.masterfile_bucket)
    end

    # S3 key prefix for audit log entries.
    def log_prefix
      ENV.fetch('S3_MIGRATION_LOG_PREFIX', 'migration-audit')
    end

    # S3 URI of the audit log prefix (for display).
    def log_path
      "s3://#{log_bucket}/#{log_prefix}/"
    end

    # Download all audit entries from S3 and write a merged CSV to +output_path+.
    # Returns the number of entries written.
    def export_csv(output_path)
      require 'csv'

      entries = list_entries
      CSV.open(output_path, 'w') do |csv|
        csv << HEADERS
        entries.each { |row| csv << row }
      end
      entries.size
    end

    # List all audit entries from S3 as arrays of field values.
    # Each S3 object may contain one or more CSV rows.
    def list_entries
      require 'csv'

      entries = []
      s3_client.list_objects_v2(bucket: log_bucket, prefix: "#{log_prefix}/").each do |page|
        page.contents.each do |obj|
          next if obj.key == "#{log_prefix}/" # skip the "directory" marker

          body = s3_client.get_object(bucket: log_bucket, key: obj.key).body.read
          CSV.parse(body).each { |row| entries << row }
        end
      end
      entries
    end

    # Count of audit S3 objects (each may contain multiple rows).
    def count
      total = 0
      s3_client.list_objects_v2(bucket: log_bucket, prefix: "#{log_prefix}/").each do |page|
        total += page.contents.count { |obj| obj.key != "#{log_prefix}/" }
      end
      total
    end

    private

    # Write one or more CSV rows as a single S3 object.
    # Key: <prefix>/<name>.csv
    # Idempotent — retried jobs overwrite the same key.
    def write_entry(name, rows)
      require 'csv'

      body = rows.map { |row| CSV.generate_line(HEADERS.map { |h| row[h.to_sym] }) }.join
      s3_client.put_object(
        bucket: log_bucket,
        key:    "#{log_prefix}/#{name}.csv",
        body:   body,
        content_type: 'text/csv'
      )
    end

    def s3_client
      @s3_client ||= Aws::S3::Client.new
    end

    # Sanitize resource IDs for use in S3 keys (replace / with _).
    def sanitize_id(id)
      id.to_s.gsub('/', '_')
    end
  end
end
# End UMD Customization
