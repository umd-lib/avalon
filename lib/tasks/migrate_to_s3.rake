# UMD Customization
#
# Rake tasks for migrating Avalon content from local filesystem to S3.
#
# Workflow:
#   1. rake avalon:migrate:s3_migration_status          # Check current state
#   2. rake avalon:migrate:enqueue_s3_migration          # Enqueue MasterFile+Derivative jobs
#   3. rake avalon:migrate:active_storage_to_s3          # Migrate SupplementalFile blobs
#   4. rake avalon:migrate:s3_migration_status          # Monitor progress
#   5. rake avalon:migrate:enqueue_s3_validation         # Post-migration checksum validation
 #   6. rake avalon:migrate:s3_migration_report           # View audit trail summary
#   7. rake avalon:migrate:validate_active_storage       # Validate ActiveStorage blobs on S3
#
# An audit trail is written automatically to S3 during steps 2 and 3.
# Each entry is stored as an individual S3 object under a configurable prefix:
#   S3_MIGRATION_LOG_BUCKET  (default: Settings.encoding.masterfile_bucket)
#   S3_MIGRATION_LOG_PREFIX  (default: migration-audit)
#
# All tasks are idempotent and safe to re-run.
#
namespace :avalon do
  namespace :migrate do

    # ── Enqueue MasterFile / Derivative migration ───────────────────────

    desc "Enqueue S3 migration jobs for all filesystem-based MasterFiles"
    task enqueue_s3_migration: :environment do
      batch_size    = ENV.fetch('BATCH_SIZE', '100').to_i
      dry_run       = ENV.fetch('DRY_RUN', 'false').casecmp('true').zero?
      filter_query  = ENV.fetch('S3_MIGRATION_FILTER_QUERY', '')
      collection    = ENV.fetch('S3_MIGRATION_COLLECTION', '')

      # Find MasterFiles that have a file_location and it does NOT start with s3://
      query = "has_model_ssim:MasterFile AND file_location_ssi:[* TO *] AND -file_location_ssi:s3\\:\\/\\/*"
      query += " AND #{filter_query}" if filter_query.present?

      # Collection filter uses Solr join — must be passed as fq, not in q
      solr_fq = collection.present? ? media_object_join_clause(collection) : nil

      start = 0
      total_enqueued = 0

      puts "Querying Solr for filesystem-based MasterFiles..."
      puts "Filter query: #{filter_query}" if filter_query.present?
      puts "Collection: #{collection}" if collection.present?
      puts "[DRY RUN] No jobs will be enqueued" if dry_run

      loop do
        solr_params = { fl: 'id,file_location_ssi', rows: batch_size, start: start }
        solr_params[:fq] = solr_fq if solr_fq
        response = ActiveFedora::SolrService.get(query, solr_params)
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
      local_root          = ENV.fetch('ACTIVE_STORAGE_LOCAL_ROOT',
                              Settings.active_storage&.root || '/masterfiles/supplemental_files/rails_active_storage')

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
            log_active_storage_migration(blob, local_root, target_service_name)
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

          # Audit trail
          log_active_storage_migration(blob, local_root, target_service_name)
        rescue => e
          errors += 1
          puts "  ERROR migrating blob #{blob.id}: #{e.class} - #{e.message}"

          # Log failure
          log_active_storage_failure(blob, local_root, target_service_name, e)
        end
      end

      puts ""
      puts "ActiveStorage migration complete: #{migrated} migrated, #{errors} error(s) out of #{total} total"
    end

    # ── Enqueue post-migration validation ───────────────────────────────

    desc "Enqueue S3 validation jobs for all migrated MasterFiles (Solr-based)"
    task enqueue_s3_validation: :environment do
      batch_size   = ENV.fetch('BATCH_SIZE', '100').to_i
      dry_run      = ENV.fetch('DRY_RUN', 'false').casecmp('true').zero?
      filter_query = ENV.fetch('S3_MIGRATION_FILTER_QUERY', '')
      collection   = ENV.fetch('S3_MIGRATION_COLLECTION', '')
      S3_MIGRATION_CUTOFF_DATE = ENV.fetch('S3_MIGRATION_CUTOFF_DATE', '')

      # Find MasterFiles whose file_location starts with s3://
      # These are the ones that have been migrated.
      query = "has_model_ssim:MasterFile AND file_location_ssi:s3\\:\\/\\/*"

      # Optional: restrict to items ingested before a cutoff date.
      # Items ingested before this date were originally on the local filesystem.
      # Format: ISO 8601, e.g. S3_MIGRATION_CUTOFF_DATE=2026-02-01T00:00:00Z
      if S3_MIGRATION_CUTOFF_DATE.present?
        query += " AND system_create_dtsi:[* TO #{S3_MIGRATION_CUTOFF_DATE}]"
        puts "Filtering to items created before #{S3_MIGRATION_CUTOFF_DATE}"
      end

      query += " AND #{filter_query}" if filter_query.present?

      # Collection filter uses Solr join — must be passed as fq, not in q
      solr_fq = collection.present? ? media_object_join_clause(collection) : nil

      start = 0
      total_enqueued = 0

      puts "Querying Solr for migrated (S3-based) MasterFiles..."
      puts "Filter query: #{filter_query}" if filter_query.present?
      puts "Collection: #{collection}" if collection.present?
      puts "[DRY RUN] No jobs will be enqueued" if dry_run

      loop do
        solr_params = { fl: 'id,file_location_ssi', rows: batch_size, start: start }
        solr_params[:fq] = solr_fq if solr_fq
        response = ActiveFedora::SolrService.get(query, solr_params)
        docs = response['response']['docs']
        break if docs.empty?

        docs.each do |doc|
          master_file_id = doc['id']
          if dry_run
            puts "  [DRY RUN] Would enqueue validation: #{master_file_id}"
          else
            ValidateS3MigrationJob.perform_later(master_file_id)
          end
          total_enqueued += 1
        end

        start += batch_size
        puts "  Processed #{start} records..." if (start % 500).zero?
      end

      puts "#{dry_run ? 'Would enqueue' : 'Enqueued'} #{total_enqueued} MasterFile(s) for S3 validation"
    end

    # ── Migration report (from S3 audit trail) ─────────────────────────

    desc "Display a summary of the S3 migration audit trail and optionally export to CSV"
    task s3_migration_report: :environment do
      require 'csv'

      puts "=== S3 Migration Audit Trail ==="
      puts "Source: #{S3MigrationLogger.log_path}"
      puts ""

      puts "Fetching audit entries from S3..."
      entries = S3MigrationLogger.list_entries
      total = entries.length

      if total.zero?
        puts "No audit entries found. Run the migration first."
        puts ""
        puts "Audit entries are written automatically to:"
        puts "  Bucket: #{S3MigrationLogger.log_bucket}"
        puts "  Prefix: #{S3MigrationLogger.log_prefix}/"
        next
      end

      # Parse entries into hashes for easy filtering
      headers = S3MigrationLogger::HEADERS
      rows = entries.map { |row| headers.zip(row).to_h }

      mf_count = rows.count { |r| r['resource_type'] == 'MasterFile' }
      d_count  = rows.count { |r| r['resource_type'] == 'Derivative' }
      as_count = rows.count { |r| r['resource_type'] == 'ActiveStorage' }
      migrated = rows.count { |r| r['status'] == 'migrated' }
      partial  = rows.count { |r| r['status'] == 'partial' }
      failed   = rows.count { |r| r['status'] == 'failed' }

      puts "Total entries:    #{total}"
      puts "  MasterFiles:    #{mf_count}"
      puts "  Derivatives:    #{d_count}"
      puts "  ActiveStorage:  #{as_count}"
      puts ""
      puts "  Migrated:       #{migrated}"
      puts "  Partial:        #{partial}" if partial > 0
      puts "  Failed:         #{failed}" if failed > 0
      puts ""

      if partial > 0
        puts "Partial migrations (MasterFile source missing, derivatives migrated):"
        rows.select { |r| r['status'] == 'partial' }.each do |r|
          mo_id = r['media_object_id'].presence || 'unknown'
          puts "  MasterFile #{r['resource_id']} (MediaObject: #{mo_id}): #{r['source_path']}"
        end
        puts ""
      end

      if failed > 0
        puts "Failed entries:"
        rows.select { |r| r['status'] == 'failed' }.each do |r|
          puts "  #{r['resource_type']} #{r['resource_id']}: #{r['error_message']}"
        end
        puts ""
      end

      # Export to local CSV if REPORT_PATH is set
      output_path = ENV['REPORT_PATH']
      if output_path.present?
        count = S3MigrationLogger.export_csv(output_path)
        puts "Exported #{count} entries to #{output_path}"
      else
        puts "Set REPORT_PATH to export the audit trail to a local CSV file."
      end

      puts "==============================="
    end

    # ── Validate ActiveStorage blobs ────────────────────────────────────

    desc "Validate ActiveStorage blobs migrated to S3 (checksum + size)"
    task validate_active_storage: :environment do
      dry_run             = ENV.fetch('DRY_RUN', 'false').casecmp('true').zero?
      target_service_name = ENV.fetch('TARGET_SERVICE', 'amazon')
      cutoff_date         = ENV.fetch('S3_MIGRATION_CUTOFF_DATE', '')

      s3_blobs = ActiveStorage::Blob.where(service_name: target_service_name)
      if cutoff_date.present?
        cutoff_time = Time.parse(cutoff_date)
        s3_blobs = s3_blobs.where("created_at < ?", cutoff_time)
        puts "Cutoff date: #{cutoff_date} — only validating blobs created before this date"
      end
      total = s3_blobs.count

      puts "Found #{total} ActiveStorage blob(s) on #{target_service_name}"

      if total.zero?
        puts "Nothing to validate."
        next
      end

      target_service = ActiveStorage::Blob.services.fetch(target_service_name)

      passed  = 0
      failed  = 0
      skipped = 0

      s3_blobs.find_each do |blob|
        # 1. Check existence on S3
        unless target_service.exist?(blob.key)
          puts "  FAIL blob #{blob.id} (#{blob.filename}): not found on S3"
          failed += 1
          next
        end

        # 2. Download and verify MD5 checksum
        #    ActiveStorage stores base64-encoded MD5 in the checksum column.
        begin
          if dry_run
            puts "  [DRY RUN] Would validate blob #{blob.id}: #{blob.filename} (#{blob.byte_size} bytes)"
            skipped += 1
            next
          end

          # Download from S3 into a tempfile and compute MD5
          blob.open do |tempfile|
            computed_md5 = Digest::MD5.file(tempfile.path).base64digest
            file_size    = File.size(tempfile.path)

            size_ok     = (file_size == blob.byte_size)
            checksum_ok = (computed_md5 == blob.checksum)

            if size_ok && checksum_ok
              puts "  PASS blob #{blob.id} (#{blob.filename}): size=#{file_size}, md5=#{computed_md5}"
              passed += 1
            else
              reasons = []
              reasons << "size mismatch (expected=#{blob.byte_size}, got=#{file_size})" unless size_ok
              reasons << "checksum mismatch (expected=#{blob.checksum}, got=#{computed_md5})" unless checksum_ok
              puts "  FAIL blob #{blob.id} (#{blob.filename}): #{reasons.join(', ')}"
              failed += 1
            end
          end
        rescue => e
          puts "  ERROR blob #{blob.id} (#{blob.filename}): #{e.class} - #{e.message}"
          failed += 1
        end
      end

      puts ""
      puts "ActiveStorage validation complete: #{passed} passed, #{failed} failed, #{skipped} skipped out of #{total} total"
    end

    # ── Status / progress reporting ─────────────────────────────────────

    desc "Show S3 migration progress for MasterFiles, Derivatives, and ActiveStorage"
    task s3_migration_status: :environment do
      cutoff_date       = ENV.fetch('S3_MIGRATION_CUTOFF_DATE', '')
      check_local_files = ENV.fetch('CHECK_LOCAL_FILES', 'false').casecmp('true').zero?
      batch_size        = ENV.fetch('BATCH_SIZE', '100').to_i
      filter_query      = ENV.fetch('S3_MIGRATION_FILTER_QUERY', '')
      collection        = ENV.fetch('S3_MIGRATION_COLLECTION', '')

      puts "=== S3 Migration Status ==="
      if cutoff_date.present?
        date_filter = " AND system_create_dtsi:[* TO #{cutoff_date}]"
        cutoff_time = Time.parse(cutoff_date)
        puts "Cutoff date: #{cutoff_date}"
        puts "  Items created before this date are filesystem-origin (migration candidates)."
        puts "  Items created after this date are S3-native (excluded from counts)."
      else
        date_filter = ""
        cutoff_time = nil
        puts "No S3_MIGRATION_CUTOFF_DATE set — counting all items."
      end

      # Optional filters applied to MasterFile/Derivative Solr queries
      extra_filter = ""
      extra_filter += " AND #{filter_query}" if filter_query.present?
      solr_fq = collection.present? ? media_object_join_clause(collection) : nil

      puts "Filter query: #{filter_query}" if filter_query.present?
      puts "Collection: #{collection}" if collection.present?
      puts ""

      # ── MasterFiles ──
      mf_total_q = "has_model_ssim:MasterFile AND file_location_ssi:[* TO *]#{date_filter}#{extra_filter}"
      mf_s3_q    = "has_model_ssim:MasterFile AND file_location_ssi:s3\\:\\/\\/*#{date_filter}#{extra_filter}"
      mf_local_q = "has_model_ssim:MasterFile AND file_location_ssi:[* TO *] AND -file_location_ssi:s3\\:\\/\\/*#{date_filter}#{extra_filter}"

      mf_total = solr_count(mf_total_q, fq: solr_fq)
      mf_s3    = solr_count(mf_s3_q, fq: solr_fq)
      mf_local = solr_count(mf_local_q, fq: solr_fq)

      puts "MasterFiles (with file_location): #{mf_total}"
      puts "  On S3:           #{mf_s3}"
      puts "  On filesystem:   #{mf_local}"
      if mf_total > 0
        puts "  Progress:        #{percentage(mf_s3, mf_total)}%"
      end
      puts ""

      # ── Derivatives ──
      d_total_q = "has_model_ssim:Derivative AND derivativeFile_ssi:[* TO *]#{date_filter}#{extra_filter}"
      d_s3_q    = "has_model_ssim:Derivative AND derivativeFile_ssi:s3\\:\\/\\/*#{date_filter}#{extra_filter}"
      d_local_q = "has_model_ssim:Derivative AND derivativeFile_ssi:file\\:\\/\\/*#{date_filter}#{extra_filter}"

      d_total = solr_count(d_total_q, fq: solr_fq)
      d_s3    = solr_count(d_s3_q, fq: solr_fq)
      d_local = solr_count(d_local_q, fq: solr_fq)

      puts "Derivatives (with derivativeFile): #{d_total}"
      puts "  On S3:           #{d_s3}"
      puts "  On filesystem:   #{d_local}"
      if d_total > 0
        puts "  Progress:        #{percentage(d_s3, d_total)}%"
      end
      puts ""

      # ── ActiveStorage blobs ──
      if defined?(ActiveStorage::Blob)
        scope = ActiveStorage::Blob.all
        scope = scope.where("created_at < ?", cutoff_time) if cutoff_time

        as_total = scope.count
        as_local = scope.where(service_name: "local").count
        as_s3    = as_total - as_local

        puts "ActiveStorage Blobs: #{as_total}"
        puts "  On S3:           #{as_s3}"
        puts "  On local disk:   #{as_local}"
        if as_total > 0
          puts "  Progress:        #{percentage(as_s3, as_total)}%"
        end
        puts ""
      end

      # ── Local file existence check ──
      if check_local_files
        puts "--- Local File Existence Check ---"
        puts ""

        # Check MasterFiles on filesystem
        mf_missing = []
        start = 0
        mf_checked = 0

        puts "Checking MasterFiles on filesystem..."
        loop do
          solr_params = { fl: 'id,file_location_ssi,isPartOf_ssim', rows: batch_size, start: start }
          solr_params[:fq] = solr_fq if solr_fq
          response = ActiveFedora::SolrService.get(mf_local_q, solr_params)
          docs = response['response']['docs']
          break if docs.empty?

          docs.each do |doc|
            file_path = doc['file_location_ssi']
            next if file_path.blank?
            mf_checked += 1

            unless File.exist?(file_path)
              media_object_title = media_object_title_for_master_file(doc)
              mf_missing << {
                id: doc['id'],
                path: file_path,
                media_object_title: media_object_title
              }
            end
          end

          start += batch_size
          puts "  Checked #{start} MasterFiles..." if (start % 500).zero?
        end

        puts "MasterFiles checked:  #{mf_checked}"
        puts "  Missing locally:    #{mf_missing.size}"
        if mf_checked > 0
          puts "  Missing:            #{percentage(mf_missing.size, mf_checked)}%"
        end

        if mf_missing.any?
          puts ""
          puts "  Missing MasterFiles:"
          mf_missing.each do |entry|
            puts "    #{entry[:id]} | #{entry[:media_object_title]} | #{entry[:path]}"
          end
        end
        puts ""

        # Check Derivatives on filesystem
        d_missing = []
        start = 0
        d_checked = 0

        puts "Checking Derivatives on filesystem..."
        loop do
          solr_params = { fl: 'id,derivativeFile_ssi,isDerivationOf_ssim', rows: batch_size, start: start }
          solr_params[:fq] = solr_fq if solr_fq
          response = ActiveFedora::SolrService.get(d_local_q, solr_params)
          docs = response['response']['docs']
          break if docs.empty?

          docs.each do |doc|
            deriv_uri = doc['derivativeFile_ssi']
            next if deriv_uri.blank?
            d_checked += 1

            begin
              local_path = Addressable::URI.parse(deriv_uri).path
            rescue
              local_path = deriv_uri.sub(%r{^file://}, '')
            end

            unless File.exist?(local_path)
              media_object_title = media_object_title_for_derivative(doc)
              d_missing << {
                id: doc['id'],
                path: local_path,
                media_object_title: media_object_title
              }
            end
          end

          start += batch_size
          puts "  Checked #{start} Derivatives..." if (start % 500).zero?
        end

        puts "Derivatives checked:  #{d_checked}"
        puts "  Missing locally:    #{d_missing.size}"
        if d_checked > 0
          puts "  Missing:            #{percentage(d_missing.size, d_checked)}%"
        end

        if d_missing.any?
          puts ""
          puts "  Missing Derivatives:"
          d_missing.each do |entry|
            puts "    #{entry[:id]} | #{entry[:media_object_title]} | #{entry[:path]}"
          end
        end
        puts ""

        # Check ActiveStorage blobs on local disk
        if defined?(ActiveStorage::Blob)
          as_scope = ActiveStorage::Blob.where(service_name: "local")
          as_scope = as_scope.where("created_at < ?", cutoff_time) if cutoff_time

          local_root = ENV.fetch('ACTIVE_STORAGE_LOCAL_ROOT',
                        Settings.active_storage&.root || '/masterfiles/supplemental_files/rails_active_storage')

          as_missing = []
          as_checked = 0

          puts "Checking ActiveStorage blobs on local disk..."
          as_scope.find_each do |blob|
            as_checked += 1
            blob_path = File.join(local_root, blob.key)

            unless File.exist?(blob_path)
              title = media_object_title_for_blob(blob)
              as_missing << {
                id: "blob-#{blob.id}",
                filename: blob.filename.to_s,
                path: blob_path,
                media_object_title: title
              }
            end
          end

          puts "ActiveStorage blobs checked: #{as_checked}"
          puts "  Missing locally:           #{as_missing.size}"
          if as_checked > 0
            puts "  Missing:                   #{percentage(as_missing.size, as_checked)}%"
          end

          if as_missing.any?
            puts ""
            puts "  Missing ActiveStorage blobs:"
            as_missing.each do |entry|
              puts "    #{entry[:id]} | #{entry[:media_object_title]} | #{entry[:filename]} | #{entry[:path]}"
            end
          end
          puts ""
        end

        puts "--- End Local File Check ---"
      end

      puts "==========================="
    end

    # ── Helpers ─────────────────────────────────────────────────────────

    # Build a Solr join clause that filters MasterFiles by their parent
    # MediaObject belonging to the given collection. Uses Solr's {!join}
    # to run the subquery server-side, scaling to any collection size.
    #
    # Example:
    #   media_object_join_clause('My Collection')
    #   => '{!join from=id to=isPartOf_ssim}has_model_ssim:MediaObject AND collection_ssim:"My Collection"'
    def media_object_join_clause(collection)
      "{!join from=id to=isPartOf_ssim}has_model_ssim:MediaObject AND collection_ssim:\"#{collection}\""
    end

    def solr_count(query, fq: nil)
      params = { rows: 0 }
      params[:fq] = fq if fq
      ActiveFedora::SolrService.get(query, params)['response']['numFound']
    end

    def percentage(numerator, denominator)
      return 0.0 if denominator.zero?
      (numerator.to_f / denominator * 100).round(1)
    end

    # Look up the parent MediaObject title from a MasterFile Solr doc.
    # MasterFile → isPartOf_ssim → MediaObject ID → title_tesi
    def media_object_title_for_master_file(solr_doc)
      media_object_ids = solr_doc['isPartOf_ssim']
      return 'Orphan item' if media_object_ids.blank?

      mo_id = media_object_ids.first
      mo_response = ActiveFedora::SolrService.get(
        "id:\"#{mo_id}\"", fl: 'title_tesi', rows: 1
      )
      mo_doc = mo_response['response']['docs'].first
      return 'Orphan item' if mo_doc.nil?

      mo_doc['title_tesi'].presence || 'Untitled'
    rescue => e
      "Error: #{e.message}"
    end

    # Look up the parent MediaObject title from a Derivative Solr doc.
    # Derivative → isDerivationOf_ssim → MasterFile → isPartOf_ssim → MediaObject
    def media_object_title_for_derivative(solr_doc)
      master_file_ids = solr_doc['isDerivationOf_ssim']
      return 'Orphan item' if master_file_ids.blank?

      mf_id = master_file_ids.first
      mf_response = ActiveFedora::SolrService.get(
        "id:\"#{mf_id}\"", fl: 'isPartOf_ssim', rows: 1
      )
      mf_doc = mf_response['response']['docs'].first
      return 'Orphan item' if mf_doc.nil?

      media_object_title_for_master_file(mf_doc)
    rescue => e
      "Error: #{e.message}"
    end

    # Look up the parent MediaObject title from an ActiveStorage blob.
    # Blob → attachment → SupplementalFile → parent_id → MediaObject
    def media_object_title_for_blob(blob)
      attachment = blob.attachments.first
      return 'Orphan item' unless attachment

      record = attachment.record
      return 'Orphan item' unless record.respond_to?(:parent_id) && record.parent_id.present?

      mo_response = ActiveFedora::SolrService.get(
        "id:\"#{record.parent_id}\"", fl: 'title_tesi', rows: 1
      )
      mo_doc = mo_response['response']['docs'].first
      return 'Orphan item' if mo_doc.nil?

      mo_doc['title_tesi'].presence || 'Untitled'
    rescue => e
      "Error: #{e.message}"
    end

    # Look up the parent MediaObject ID for an ActiveStorage blob.
    # SupplementalFile stores parent_id which is the MediaObject ID.
    def media_object_id_for_blob(blob)
      attachment = blob.attachments.first
      return nil unless attachment
      record = attachment.record
      if record.respond_to?(:parent_id)
        master_file = MasterFile.find(record.parent_id)
        if master_file.present?
          return master_file.media_object.id if master_file.media_object
        else
          record.parent_id
        end
      else
        nil
      end
    rescue => e
      puts "  WARNING: Failed to determine media_object_id for blob #{blob.id}: #{e.message}"
      nil
    end

    # Log a successful ActiveStorage blob migration to the audit CSV.
    def log_active_storage_migration(blob, local_root, target_service_name)
      S3MigrationLogger.log_migration(
        resource_id:     "blob-#{blob.id}",
        resource_type:   'ActiveStorage',
        media_object_id: media_object_id_for_blob(blob),
        source_path:     File.join(local_root, blob.key),
        destination_uri: "s3://#{Settings.active_storage&.bucket || target_service_name}/#{blob.key}",
        file_size:       blob.byte_size,
        checksum:        blob.checksum,
        checksum_type:   'MD5'
      )
    rescue => e
      puts "  WARNING: Failed to log audit entry for blob #{blob.id}: #{e.message}"
    end

    # Log a failed ActiveStorage blob migration to the audit CSV.
    def log_active_storage_failure(blob, local_root, target_service_name, error)
      S3MigrationLogger.log_failure(
        resource_id:     "blob-#{blob.id}",
        resource_type:   'ActiveStorage',
        media_object_id: media_object_id_for_blob(blob),
        source_path:     File.join(local_root, blob.key),
        destination_uri: "s3://#{Settings.active_storage&.bucket || target_service_name}/#{blob.key}",
        error_message:   "#{error.class}: #{error.message}"
      )
    rescue => e
      puts "  WARNING: Failed to log audit failure for blob #{blob.id}: #{e.message}"
    end

  end
end
# End UMD Customization
