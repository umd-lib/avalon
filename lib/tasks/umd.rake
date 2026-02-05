require 'move_dropbox_files_to_archive'

namespace :umd do
  desc "Move master files from dropbox directory to archive"
  task :move_dropbox_files_to_archive => :environment do
    archive_dir = Settings.master_file_management.path
    raise '"path" configuration missing for master_file_management strategy "move"' if archive_dir.blank?

    # additionally support "no" as a false boolean value
    ENV['dry_run'] = 'false' if ENV['dry_run'].in? %w[no NO]

    dry_run = ActiveModel::Type::Boolean.new.cast(ENV['dry_run'])

    Rails.logger.tagged("move_dropbox_files_to_archive") do
      Rails.logger.info("Starting move_dropbox_files_to_archive, dry_run=#{dry_run}")
      move_dropbox_files_to_archive(archive_dir, dry_run)
      Rails.logger.info("Done move_dropbox_files_to_archive")
    end
  end

  desc "Ensure S3 dropbox folders exist for all collections"
  task ensure_collection_s3_bucket: :environment do
    # Ensure Avalon is configured with S3 backend
    unless Settings.encoding.masterfile_bucket.present?
      Rails.logger.info("Avalon is NOT configured with S3 backend")
      return
    end
    # For each collection, ensure a S3 Prefix for dropbox path exists
    Admin::Collection.find_each do |collection|
      collection.ensure_collection_s3_bucket
    end
  end

  desc "Cancel and requeue active encode jobs"
  task cancel_and_requeue_active_encode_jobs: :environment do
    encodes = ActiveEncode::EncodeRecord.where(state: 'running').where('updated_at >= ?', 24.hours.ago)

    cancelled_count = 0
    encodes.each do |encode_record|
      global_id = encode_record.global_id
      uuid = global_id.split('/').last
      encode_dir = File.join(ENV['ENCODE_WORK_DIR'], uuid)
      if Dir.exist?(encode_dir)
        master_file = MasterFile.find(encode_record.master_file_id)
        workflow_id = master_file&.workflow_id
        # Cancel the running encode job
        ActiveEncodeJobs::CancelEncodeJob.perform_now(workflow_id, master_file.id) if workflow_id.present? && !master_file.finished_processing?
        cancelled_count += 1
        # Requeue the master file for processing
        master_file.workflow_id = nil
        master_file.save
        master_file.process
      end
    end
    Rails.logger.info("Cancelled and requeued #{cancelled_count} of running encodes on this worker.")
  end

  desc "Process running encodes on distributed workers"
  task process_running_encodes: :environment do
    # Find encode records in 'running' state within the 24 hours
    encodes = ActiveEncode::EncodeRecord.where(state: 'running').where('updated_at >= ?', 24.hours.ago)

    state_change_counts = Hash.new
    # For each running encode, process it if the encode dir exists in the current worker
    processed_encodes = encodes.filter_map do |encode_record|
      global_id = encode_record.global_id
      uuid = global_id.split('/').last
      encode_dir = File.join(ENV['ENCODE_WORK_DIR'], uuid)
      if Dir.exist?(encode_dir)
        encode = FfmpegEncode.find(uuid)
        process_encode(encode)
        if encode.state.to_s != "running"
          state_change_counts[encode.state.to_s]   ||= 0
          state_change_counts[encode.state.to_s]   += 1
          Rails.logger.info("Encode #{encode.id} changed state to #{encode.state} on this worker.")
        end
        encode
      end
    end
    Rails.logger.info("Processed #{processed_encodes.count} running encodes on this worker.")
    state_change_counts.each do |state, count|
      Rails.logger.info(" - #{count} encodes changed to state #{state}.")
    end
  end

  desc "List orphaned archived master files in S3."
  task list_orphaned_archived_master_files: :environment do
    orphaned_files, bucket_name = get_orphaned_master_files
    if orphaned_files.empty?
      Rails.logger.info("No orphaned archived master files found in S3.")
    else
      Rails.logger.info("Orphaned archived master files in S3:")
      orphaned_files.each do |file_key|
        Rails.logger.info(" - s3://#{bucket_name}/#{file_key}")
      end
      Rails.logger.info("Total orphaned files: #{orphaned_files.count}")
    end
  end

  desc "Delete orphaned archived master files in S3."
  task delete_orphaned_archived_master_files: :environment do
    orphaned_files, bucket_name = get_orphaned_master_files
    if orphaned_files.empty?
      Rails.logger.info("No orphaned archived master files found in S3.")
    else
      Rails.logger.info("Found #{orphaned_files.count} orphaned archived master files from S3:")
      Rails.logger.info("You can list them using the rake task 'umd:list_orphaned_archived_master_files'.")

      # Get user confirmation before proceeding
      puts "\nAre you sure you want to delete #{orphaned_files.count} orphaned archived master files from S3? (yes/no)"
      confirmation = STDIN.gets.chomp
      unless confirmation.downcase == 'yes'
        Rails.logger.info("Deletion of orphaned archived master files cancelled by user.")
        next
      end

      s3_client = Aws::S3::Client.new
      Rails.logger.info("Deleting #{orphaned_files.count} orphaned archived master files from S3:")
      orphaned_files.each do |file_key|
        begin
          s3_client.delete_object(bucket: bucket_name, key: file_key)
          Rails.logger.info(" - Deleted s3://#{bucket_name}/#{file_key}")
        rescue => e
          Rails.logger.error(" - Failed to delete s3://#{bucket_name}/#{file_key}, reason: #{e.message}")
        end
      end
    end
  end
end

def process_encode(encode)
  encode.run_callbacks(:status_update) { encode }
  case encode.state
  when :failed
    encode.run_callbacks(:failed) { encode }
  when :cancelled
    encode.run_callbacks(:cancelled) { encode }
  when :completed
    encode.run_callbacks(:completed) { encode }
  when :running
    # no-op
  else # other states are illegal and ignored
    raise StandardError, "Illegal state #{encode.state} in encode #{encode.id}!"
  end
end

def move_dropbox_files_to_archive(archive_dir, dry_run=false)
  perform_result = MoveDropboxFilesToArchive.perform(archive_dir, dry_run)

  total_files = perform_result.drop_box_files_hash.count
  num_files_to_migrate = perform_result.filter_files_result.files_to_migrate.count
  num_files_missing = perform_result.filter_files_result.missing_files.count
  num_files_skipped = perform_result.filter_files_result.skipped_files.count
  num_migrated = perform_result.migrate_drop_box_files_result.successful_migrations.count
  num_migration_failed = perform_result.migrate_drop_box_files_result.failed_migrations.count
  num_deleted = perform_result.delete_files_result.successful_deletes.count
  num_deleted_failed = perform_result.delete_files_result.failed_deletes.count

  puts "Total files: #{total_files}"
  puts "Files skipped (already archived): #{num_files_skipped}"
  puts "Files needing migration: #{num_files_to_migrate}"

  if num_files_missing > 0
    puts "---------"
    puts "Missing Files"
    puts "---------"
    perform_result.filter_files_result.missing_files.each do |result|
      puts "#{result.dropbox_file_location}, master_file_ids: #{result.master_file_ids}"
    end
  end

  if (dry_run)
    puts "---------"
    puts "Files to Migrate (Dry Run)"
    puts "---------"
    perform_result.filter_files_result.files_to_migrate.each do |result|
      puts "#{result.dropbox_file_location}, master_file_ids: #{result.master_file_ids}"
    end
    return
  end

  puts "Files migrated: #{num_migrated}"
  if num_migrated > 0
    puts "---------"
    puts "Successful Migrations (#{num_migrated})"
    puts "---------"
    perform_result.migrate_drop_box_files_result.successful_migrations.each do |result|
      puts "#{result.dropbox_file_location}, master_file_ids: #{result.master_file_ids}, archive_locations: #{result.archive_locations}"
    end
  end

  if num_migration_failed > 0
    puts "---------"
    puts "Failed Migrations (#{num_migration_failed})"
    puts "---------"
    perform_result.migrate_drop_box_files_result.failed_migrations.each do |result|
      result.errors.each do |error|
        puts "Failed migration of #{error.dropbox_file_location} to #{error.archive_location} for #{error.master_file_id}, reason: #{error.reason}"
      end
    end
  end

  puts "Files deleted: #{num_deleted}"
  if num_deleted > 0
    puts "---------"
    puts "Successful Deletions (#{num_migrated})"
    puts "---------"
    perform_result.delete_files_result.successful_deletes.each do |result|
      puts "#{result.dropbox_file_location}, master_file_ids: #{result.master_file_ids}, archive_locations: #{result.archive_locations}"
    end
  end

  if num_deleted_failed > 0
    puts "---------"
    puts "Failed Deletions (#{num_deleted_failed})"
    puts "---------"
    perform_result.delete_files_result.failed_deletes.each do |result|
      result.errors.each do |error|
        puts "Failed deletion of #{error.dropbox_file_location}, master_file_ids: #{result.master_file_ids}, reason: #{error.reason}"
      end
    end
  end
end

def get_orphaned_master_files
  # Get all archived master files in S3
  s3_base_path = Settings.master_file_management.path
  s3_client = Aws::S3::Client.new
  s3_resource = Aws::S3::Resource.new(client: s3_client)
  bucket_name = Settings.encoding.masterfile_bucket
  bucket = s3_resource.bucket(bucket_name)
  prefix = Addressable::URI.parse(s3_base_path).path.sub(%r{^/}, '')
  
  # Build a Set of master file archived paths for O(1) lookup
  # Query Solr directly to avoid loading ActiveFedora objects (much faster and more memory efficient)
  master_file_archived_paths = Set.new
  
  # Query Solr in batches to get all master files with file_location containing the archive path
  start = 0
  batch_size = 5000
  loop do
    # Query for MasterFiles with file_location starting with the s3 archive path
    # file_location_ssi is a stored, sortable string field in Solr
    query = "has_model_ssim:MasterFile AND file_location_ssi:s3\\:\\/\\/#{bucket_name}\\/#{prefix.gsub('/', '\\/')}*"
    response = ActiveFedora::SolrService.get(query, fl: 'file_location_ssi', rows: batch_size, start: start)
    docs = response['response']['docs']
    
    break if docs.empty?
    
    docs.each do |doc|
      next unless doc['file_location_ssi'].present?
      # Extract the S3 key from the full S3 URI (e.g., "s3://bucket/path/file.mp4" -> "path/file.mp4")
      uri = Addressable::URI.parse(doc['file_location_ssi'])
      path = uri.path.sub(%r{^/}, '')
      master_file_archived_paths.add(path)
    end
    
    start += batch_size
  end

  # Stream through S3 objects and identify orphaned files without loading all into memory
  orphaned_files = []
  bucket.objects(prefix: prefix).each do |obj|
    orphaned_files << obj.key unless master_file_archived_paths.include?(obj.key)
  end
  
  [orphaned_files, bucket_name]
end

