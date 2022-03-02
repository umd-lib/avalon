class DropBoxFile
  # Encapsulates the information about a drop box file, and the actions
  # that can be taken on it.

  attr_reader :dropbox_file_location, :archive_locations, :errors

  def initialize(dropbox_file_location)
    @dropbox_file_location = dropbox_file_location
    @master_files = []
    @errors = []
    @archive_locations = []
    @master_files_updated = []
    @migration_successful = false
    @deleted = false
  end

  def add_master_file(master_file)
    # Associates the given MasterFile with this object
    @master_files.push(master_file)
  end

  def migrate_file(archive_directory)
    # Copies the associated dropbox file to the archive directory (the file is
    # copied once for each MasterFile), and updates the MasterFiles. Returns
    # true if the migration succeeds, false otherwise. If the migration fails,
    # a MigrationError is added to the "errors" field of this object.
    @migration_successful = true
    @master_files.each do |master_file|
      archive_location = File.join(archive_directory,
                                    MasterFile.post_processing_move_relative_filepath(@dropbox_file_location, { id: master_file.id }))
      begin
        FileUtils.mkdir_p(File.dirname(archive_location))
        FileUtils.cp(@dropbox_file_location, archive_location, preserve: true)
        master_file.file_location = archive_location
        master_file.save!
        @master_files_updated.push(master_file.id)
        @archive_locations.push(archive_location)
        Rails.logger.info("Successful migration of #{@dropbox_file_location} to #{archive_location} for #{master_file.id}")
      rescue Exception => e
        @errors.push(MigrationError.new(master_file_id: master_file.id,
                                dropbox_file_location: @dropbox_file_location,
                                archive_location: archive_location,
                                reason: e.message))
        @migration_successful = false
        Rails.logger.info("Failed migration of #{@dropbox_file_location} to #{archive_location} for #{master_file.id}, reason: #{e.message}")
      end
    end
    return @migration_successful
  end

  def can_delete?
    # Returns true if all operations on this object have been successful, and
    # therefore the file can be deleted, false otherwise.
    @errors.empty? && @migration_successful
  end

  def delete_file
    # Deletes the file in the dropbox directory, returning true if the file was
    # successfully deleted, false otherwise. If the deletion fails, a
    # DeletionError is added to the "errors" field of this object.
    @deleted = false
    if can_delete?
      begin
        FileUtils.rm(@dropbox_file_location)
        @deleted = true
        Rails.logger.info("Successful delete of #{@dropbox_file_location}")
      rescue Exception => e
        @errors.push(DeletionError.new(dropbox_file_location: "#{@dropbox_file_location}", reason: e.message))
        Rails.logger.info("Delete failed for #{@dropbox_file_location}")
      end
    end
    return @deleted
  end

  def master_file_ids
    # Returns a list of the MasterFile ids associated with this object.
    @master_files.map(&:id)
  end

  def to_s
    # Returns a String reprsentation of this object.
    master_files_updated_ids = @master_files_updated
    "DropBoxFile: [" +
      "dropbox_file_location: #{@dropbox_file_location}, " +
      "master_file_ids: #{master_file_ids}, " +
      "archive_locations: #{@archive_locations}, " +
      "master_files_updated_ids: #{master_files_updated_ids}, " +
      "migration_successful: #{@migration_successful}, " +
      "deleted: #{@deleted}, " +
      "errors: #{@errors}" +
    "]"
  end
end

class MoveDropboxFilesToArchive
  # Performs the operations needed by the "umd:move_dropbox_files_to_archive"
  # Rake task

  def self.create_drop_box_files_hash()
    # Queries all the MasterFiles, returning a hash of DropBoxFile objects,
    # indexed by the file location.
    drop_box_files_hash = {}

    MasterFile.all.each do |master_file|
      file_location = master_file.file_location
      if file_location
        drop_box_file = drop_box_files_hash.fetch(file_location, DropBoxFile.new(file_location))
        drop_box_file.add_master_file(master_file)
        drop_box_files_hash[file_location] = drop_box_file
      end
    end
    drop_box_files_hash
  end

  def self.filter_drop_box_files(archive_dir, drop_box_files_hash)
    # Returns a FilterFileResult object, containing:
    #   file_to_migrate: A list of DropBoxFile objects to migrate (i.e., the
    #      associated file is in a dropbox directory)
    #   missing_files: A list of DropBoxFile objects where the file could not
    #      be found
    #   skipped_files: A list of DropBoxFile objects where the file is already
    #      in the archive directory, and so does not need to be moved.
    skipped_files = []
    missing_files = []
    files_to_migrate = []
    drop_box_files_hash.each do |file_location, drop_box_file|
      if file_location.start_with?(archive_dir)
        skipped_files.push(drop_box_file)
        next
      end

      unless File.exist?(file_location)
        missing_files.push(drop_box_file)
        next
      end

      files_to_migrate.push(drop_box_file)
    end
    FilterFilesResult.new(files_to_migrate: files_to_migrate, missing_files: missing_files, skipped_files: skipped_files)
  end

  def self.migrate_drop_box_files(archive_dir, files_to_migrate)
    # Migrates all DropBoxFiles in the given "files_to_migrate" list to the
    # appropriate directory the given "archive_dir" base directory.
    #
    # Returns a MigrateDropBoxFilesResult object containing:
    #   successful_migrations: A list of DropBoxFiles that were successfully
    #     migrated.
    #   failed_migrations: A list of DropBoxFiles that failed to migrate. The
    #     "errors" field of the objects will be populated with the specific
    #     error.
    successful_migrations = []
    failed_migrations = []
    files_to_migrate.each do |f|
      if f.migrate_file(archive_dir)
        successful_migrations.push(f)
      else
        failed_migrations.push(f)
      end
    end

    MigrateDropBoxFilesResult.new(successful_migrations: successful_migrations, failed_migrations: failed_migrations)
  end

  def self.delete_files(successful_migrations)
    # Deletes all DropBoxFiles in the given "successful_migrations" list.
    #
    # Returns a DeleteFilesResult object containing:
    #   successful_deletes: A list of DropBoxFiles that were successfully
    #     deleted.
    #   failed_deletes: A list of DropBoxFiles that failed to delete. The
    #     "errors" field of the objects will be populated with the specific
    #     error.
    successful_deletes = []
    failed_deletes = []

    successful_migrations.each do |f|
      if f.delete_file
        successful_deletes.push(f)
      else
        failed_deletes.push(f)
      end
    end
    DeleteFilesResult.new(successful_deletes: successful_deletes, failed_deletes: failed_deletes)
  end

  def self.perform(archive_dir, dry_run=false)
    # Main function, called to perform the actual migration steps, migrating
    # the files into the given "archive_dir" base directory.
    #
    # If the "dry_run" parameter is true, only information about the number of
    # files to be moved will be returned -- there will be no change to the
    # files.
    #
    # Returns a PerformResult containing all the information generated by the
    # migration steps:
    #   drop_box_files_hash: the hash of DropBoxFile objects considered for
    #     migration, indexed by the file location.
    #   filter_files_result: the FilterFilesResult, containing the files to be
    #     migrated, missing files, and skipped files
    #   migrate_drop_box_files_result: the MigrateDropBoxFilesResult, containing
    #     the successful and failed migrations
    #   delete_files_result: the DeleteFilesResult, containing the successful
    #     and failed deletions
    drop_box_files_hash = create_drop_box_files_hash()
    filter_files_result = filter_drop_box_files(archive_dir, drop_box_files_hash)

    if dry_run
      return PerformResult.new(drop_box_files_hash: drop_box_files_hash,
                               filter_files_result: filter_files_result,
                               migrate_drop_box_files_result: MigrateDropBoxFilesResult.new(
                                 successful_migrations: [], failed_migrations: []
                               ),
                               delete_files_result: DeleteFilesResult.new(
                                 successful_deletes: [], failed_deletes: []
                               ))
    end

    migrate_drop_box_files_result = migrate_drop_box_files(archive_dir, filter_files_result.files_to_migrate)
    delete_files_result = delete_files(migrate_drop_box_files_result.successful_migrations)

    PerformResult.new(drop_box_files_hash: drop_box_files_hash,
                      filter_files_result: filter_files_result,
                      migrate_drop_box_files_result: migrate_drop_box_files_result,
                      delete_files_result: delete_files_result)
  end
end

FilterFilesResult = Struct.new(:files_to_migrate, :missing_files, :skipped_files, keyword_init: true)
MigrateDropBoxFilesResult = Struct.new(:successful_migrations, :failed_migrations, keyword_init: true)
DeleteFilesResult = Struct.new(:successful_deletes, :failed_deletes, keyword_init: true)
PerformResult = Struct.new(:drop_box_files_hash, :filter_files_result, :migrate_drop_box_files_result, :delete_files_result, keyword_init: true)

MigrationError = Struct.new(:master_file_id, :dropbox_file_location, :archive_location, :reason, keyword_init: true)
DeletionError = Struct.new(:dropbox_file_location, :reason, keyword_init: true )
