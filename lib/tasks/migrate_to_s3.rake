# UMD Customization
#
# Rake tasks for migrating Avalon content from local filesystem to S3.
#
# Workflow:
#   1. rake avalon:migrate:s3_migration_status          # Check current state
#   2. rake avalon:migrate:enqueue_s3_migration          # Enqueue MasterFile+Derivative jobs
#   3. rake avalon:migrate:active_storage_to_s3          # Migrate SupplementalFile blobs
#   4. rake avalon:migrate:s3_migration_status          # Monitor progress
#
# All tasks are idempotent and safe to re-run.
#
namespace :avalon do
  namespace :migrate do

    # ── Enqueue MasterFile / Derivative migration ───────────────────────

    desc "Enqueue S3 migration jobs for all filesystem-based MasterFiles"
    task enqueue_s3_migration: :environment do
      batch_size = ENV.fetch('BATCH_SIZE', '100').to_i
      dry_run    = ENV.fetch('DRY_RUN', 'false').casecmp('true').zero?

      # Find MasterFiles that have a file_location and it does NOT start with s3://
      query = "has_model_ssim:MasterFile AND file_location_ssi:[* TO *] AND -file_location_ssi:s3\\:\\/\\/*"
      start = 0
      total_enqueued = 0

      puts "Querying Solr for filesystem-based MasterFiles..."
      puts "[DRY RUN] No jobs will be enqueued" if dry_run

      loop do
        response = ActiveFedora::SolrService.get(query, fl: 'id,file_location_ssi', rows: batch_size, start: start)
        docs = response['response']['docs']
        break if docs.empty?

        docs.each do |doc|
          next if doc['file_location_ssi'].blank?

          master_file_id = doc['id']
          if dry_run
            puts "  [DRY RUN] Would enqueue: #{master_file_id} (#{doc['file_location_ssi']})"
          else
            MigrateToS3Job.perform_later(master_file_id)
          end
          total_enqueued += 1
        end

        start += batch_size
        puts "  Processed #{start} records..." if (start % 500).zero?
      end

      puts "#{dry_run ? 'Would enqueue' : 'Enqueued'} #{total_enqueued} MasterFile(s) for S3 migration"
    end

    # ── ActiveStorage blob migration ────────────────────────────────────

    desc "Migrate ActiveStorage blobs from local disk to S3"
    task active_storage_to_s3: :environment do
      dry_run             = ENV.fetch('DRY_RUN', 'false').casecmp('true').zero?
      target_service_name = ENV.fetch('TARGET_SERVICE', 'amazon')

      local_blobs = ActiveStorage::Blob.where(service_name: "local")
      total = local_blobs.count

      puts "Found #{total} ActiveStorage blob(s) on local disk"
      puts "[DRY RUN] No blobs will be migrated" if dry_run
      puts "Target service: #{target_service_name}"

      if total.zero?
        puts "Nothing to migrate."
        next
      end

      target_service = ActiveStorage::Blob.services.fetch(target_service_name)

      migrated = 0
      errors   = 0

      local_blobs.find_each do |blob|
        if dry_run
          puts "  [DRY RUN] Would migrate blob #{blob.id}: #{blob.filename} (#{blob.byte_size} bytes)"
          migrated += 1
          next
        end

        begin
          # If the file already exists in the target (e.g. partial previous run),
          # just update the service_name
          if target_service.exist?(blob.key)
            puts "  Blob #{blob.id} already exists in #{target_service_name}, updating record"
            blob.update_column(:service_name, target_service_name)
            migrated += 1
            next
          end

          # Download from local disk service and upload to S3
          blob.open do |tempfile|
            target_service.upload(blob.key, tempfile, checksum: blob.checksum)
          end

          # Verify
          unless target_service.exist?(blob.key)
            raise "Upload verification failed for blob #{blob.id}"
          end

          blob.update_column(:service_name, target_service_name)
          migrated += 1
          puts "  Migrated blob #{blob.id}: #{blob.filename}"
        rescue => e
          errors += 1
          puts "  ERROR migrating blob #{blob.id}: #{e.class} - #{e.message}"
        end
      end

      puts ""
      puts "ActiveStorage migration complete: #{migrated} migrated, #{errors} error(s) out of #{total} total"
    end

    # ── Status / progress reporting ─────────────────────────────────────

    desc "Show S3 migration progress for MasterFiles, Derivatives, and ActiveStorage"
    task s3_migration_status: :environment do
      puts "=== S3 Migration Status ==="
      puts ""

      # ── MasterFiles ──
      mf_total_q = "has_model_ssim:MasterFile AND file_location_ssi:[* TO *]"
      mf_s3_q    = "has_model_ssim:MasterFile AND file_location_ssi:s3\\:\\/\\/*"
      mf_local_q = "has_model_ssim:MasterFile AND file_location_ssi:[* TO *] AND -file_location_ssi:s3\\:\\/\\/*"

      mf_total = solr_count(mf_total_q)
      mf_s3    = solr_count(mf_s3_q)
      mf_local = solr_count(mf_local_q)

      puts "MasterFiles (with file_location): #{mf_total}"
      puts "  On S3:           #{mf_s3}"
      puts "  On filesystem:   #{mf_local}"
      if mf_total > 0
        puts "  Progress:        #{percentage(mf_s3, mf_total)}%"
      end
      puts ""

      # ── Derivatives ──
      d_total_q = "has_model_ssim:Derivative AND derivativeFile_ssi:[* TO *]"
      d_s3_q    = "has_model_ssim:Derivative AND derivativeFile_ssi:s3\\:\\/\\/*"
      d_local_q = "has_model_ssim:Derivative AND derivativeFile_ssi:file\\:\\/\\/*"

      d_total = solr_count(d_total_q)
      d_s3    = solr_count(d_s3_q)
      d_local = solr_count(d_local_q)

      puts "Derivatives (with derivativeFile): #{d_total}"
      puts "  On S3:           #{d_s3}"
      puts "  On filesystem:   #{d_local}"
      if d_total > 0
        puts "  Progress:        #{percentage(d_s3, d_total)}%"
      end
      puts ""

      # ── ActiveStorage blobs ──
      if defined?(ActiveStorage::Blob)
        as_total = ActiveStorage::Blob.count
        as_local = ActiveStorage::Blob.where(service_name: "local").count
        as_s3    = as_total - as_local

        puts "ActiveStorage Blobs: #{as_total}"
        puts "  On S3:           #{as_s3}"
        puts "  On local disk:   #{as_local}"
        if as_total > 0
          puts "  Progress:        #{percentage(as_s3, as_total)}%"
        end
        puts ""
      end

      puts "==========================="
    end

    # ── Helpers ─────────────────────────────────────────────────────────

    def solr_count(query)
      ActiveFedora::SolrService.get(query, rows: 0)['response']['numFound']
    end

    def percentage(numerator, denominator)
      return 0.0 if denominator.zero?
      (numerator.to_f / denominator * 100).round(1)
    end

  end
end
# End UMD Customization
