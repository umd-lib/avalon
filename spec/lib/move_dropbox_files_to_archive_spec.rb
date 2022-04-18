require 'rails_helper'
require 'fileutils'
require 'move_dropbox_files_to_archive'

describe 'MoveDropboxFilesToArchive - Integration test' do
  before(:each) do
    @temp_dir = Dir.mktmpdir
    @temp_archive_dir = "#{@temp_dir}/archive"
    FileUtils.cp_r('spec/fixtures/move_dropbox_files/.', @temp_dir)

    @assets_dir = "#{@temp_dir}/dropbox/Sample_Collection/assets"
    @dropbox_success1 = "#{@assets_dir}/sample_success1.mp4"
    @dropbox_success2 = "#{@assets_dir}/sample_success2.mp4"
    @dropbox_two_master_files = "#{@assets_dir}/sample_with_two_master_files.mp4"
    @dropbox_copy_fails = "#{@assets_dir}/sample_copy_fails.mp4"
    @dropbox_update_fails = "#{@assets_dir}/sample_master_file_update_fails.mp4"
    @dropbox_delete_fails = "#{@assets_dir}/sample_delete_fails.mp4"

    @dropbox_missing = "#{@assets_dir}/missing.mp4"
    @archived_file = "#{@temp_archive_dir}/sample_archived.mp4"

    @master_file_success1 = FactoryBot.create(:master_file, file_location: @dropbox_success1)
    @master_file_success2 = FactoryBot.create(:master_file, file_location: @dropbox_success2)
    @master_file_two_master_files1 = FactoryBot.create(:master_file, file_location: @dropbox_two_master_files)
    @master_file_two_master_files2 = FactoryBot.create(:master_file, file_location: @dropbox_two_master_files)
    @master_file_copy_fails = FactoryBot.create(:master_file, file_location: @dropbox_copy_fails)
    @master_file_update_fails = FactoryBot.create(:master_file, file_location: @dropbox_update_fails)
    @master_file_delete_fails = FactoryBot.create(:master_file, file_location: @dropbox_delete_fails)

    @master_file_missing = FactoryBot.create(:master_file, file_location: @dropbox_missing)
    @master_file_archived = FactoryBot.create(:master_file, file_location: @archived_file)

    @archived_file_update_fails = File.join(@temp_archive_dir, MasterFile.post_processing_move_relative_filepath(@dropbox_update_fails, id: @master_file_update_fails.id))

    # Expected location of archived files
    @expected_archived_file_success1 = File.join(@temp_archive_dir, MasterFile.post_processing_move_relative_filepath(@dropbox_success1, id: @master_file_success1.id))
    @expected_archived_file_success2 = File.join(@temp_archive_dir, MasterFile.post_processing_move_relative_filepath(@dropbox_success2, id: @master_file_success2.id))
    @expected_archived_file_two_master_files1 = File.join(@temp_archive_dir, MasterFile.post_processing_move_relative_filepath(@dropbox_two_master_files, id: @master_file_two_master_files1.id))
    @expected_archived_file_two_master_files2 = File.join(@temp_archive_dir, MasterFile.post_processing_move_relative_filepath(@dropbox_two_master_files, id: @master_file_two_master_files2.id))
    @expected_archived_file_copy_fails = File.join(@temp_archive_dir, MasterFile.post_processing_move_relative_filepath(@dropbox_copy_fails, id: @master_file_copy_fails.id))
    @expected_archived_file_update_fails = File.join(@temp_archive_dir, MasterFile.post_processing_move_relative_filepath(@dropbox_update_fails, id: @master_file_update_fails.id))
    @expected_archived_file_delete_fails = File.join(@temp_archive_dir, MasterFile.post_processing_move_relative_filepath(@dropbox_delete_fails, id: @master_file_delete_fails.id))
  end

  describe '#perform' do
    it 'an actual run correctly moves the files and updates the MasterFile records, despite' do
      # Force copy_files failure for master_file_copy_fails
      allow(FileUtils).to receive(:cp).and_call_original
      allow(FileUtils).to receive(:cp).with(@master_file_copy_fails.file_location, anything, preserve: true).and_raise(Exception)

      # Force update_master_files failure for master_file_update_fails
      allow_any_instance_of(MasterFile).to receive(:file_location=).and_call_original
      allow_any_instance_of(MasterFile).to receive(:file_location=).with(@archived_file_update_fails).and_raise(Exception)

      # Force delete_files failure for master_file_delete_fails
      allow(FileUtils).to receive(:rm).and_call_original
      allow(FileUtils).to receive(:rm).with(@master_file_delete_fails.file_location).and_raise(Exception)

      perform_result = MoveDropboxFilesToArchive.perform(@temp_archive_dir)

      # Total files includes missing files, and file already archived,
      # but counts each file only once (where two MasterFiles are pointed
      # at the same file.
      total_files = perform_result.drop_box_files_hash.count
      expect(total_files).to eq(8)

      # Files to migrate does not include missing file or file in archive
      num_files_to_migrate = perform_result.filter_files_result.files_to_migrate.count
      expect(num_files_to_migrate).to eq(6)

      num_files_missing = perform_result.filter_files_result.missing_files.count
      expect(num_files_missing).to eq(1)

      num_files_skipped = perform_result.filter_files_result.skipped_files.count
      expect(num_files_skipped).to eq(1)

      # Number migrated does not include copy or master_file update failures
      num_migrated = perform_result.migrate_drop_box_files_result.successful_migrations.count
      expect(num_migrated).to eq(4)

      num_migration_failed = perform_result.migrate_drop_box_files_result.failed_migrations.count
      expect(num_migration_failed).to eq(2)

      # Number deleted does not include deletion failures
      num_deleted = perform_result.delete_files_result.successful_deletes.count
      expect(num_deleted).to eq(3)

      num_deleted_failed = perform_result.delete_files_result.failed_deletes.count
      expect(num_deleted_failed).to eq(1)

      dropbox_files_base_names = []
      Dir.chdir("#{@temp_dir}/dropbox") do
        dropbox_files = Dir.glob("**/*.mp4").reject {|fn| File.directory?(fn) }
        dropbox_files_base_names = dropbox_files.map { |f| File.basename(f) }
      end

      archive_files_base_names = []
      Dir.chdir(@temp_archive_dir) do
        archive_files = Dir.glob("**/*.mp4").reject {|fn| File.directory?(fn) }
        archive_files_base_names = archive_files.map { |f| File.basename(f) }
        archive_files_base_names = archive_files_base_names.map { |f| f.gsub(/.*\-(.*)/, '\1') }
      end

      expected_dropbox_base_filenames = [
        "sample_delete_fails.mp4",
        "sample_master_file_update_fails.mp4",
        "sample_copy_fails.mp4"
      ]

      expected_archive_base_filenames =  [
        "sample_success1.mp4",
        "sample_success2.mp4",
        "sample_master_file_update_fails.mp4",
        "sample_delete_fails.mp4",
        # Following file occurs twice because two master files reference the
        # same dropbox file
        "sample_with_two_master_files.mp4",
        "sample_with_two_master_files.mp4",
      ]

      expect(dropbox_files_base_names).to match_array(expected_dropbox_base_filenames)
      expect(archive_files_base_names).to match_array(expected_archive_base_filenames)
    end
  end

  after(:each) do
    FileUtils.remove_entry_secure(@temp_dir, force = false)
  end
end
