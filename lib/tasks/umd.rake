require 'move_dropbox_files_to_archive'

namespace :umd do
  desc "Move master files from dropbox directory to archive"
  task :move_dropbox_files_to_archive, %i[dry_run] => :environment do |_t, args|
    args.with_defaults(:dry_run => 'false')

    archive_dir = Settings.master_file_management.path
    raise '"path" configuration missing for master_file_management strategy "move"' if archive_dir.blank?

    dry_run = ActiveModel::Type::Boolean.new.cast(args.dry_run)

    Rails.logger.tagged("move_dropbox_files_to_archive") do
      Rails.logger.info("Starting move_dropbox_files_to_archive, dry_run=#{dry_run}")
      move_dropbox_files_to_archive(archive_dir, dry_run)
      Rails.logger.info("Done move_dropbox_files_to_archive")
    end
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

