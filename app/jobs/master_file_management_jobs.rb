# Copyright 2011-2025, The Trustees of Indiana University and Northwestern
#   University.  Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#   CONDITIONS OF ANY KIND, either express or implied. See the License for the
#   specific language governing permissions and limitations under the License.
# ---  END LICENSE_HEADER BLOCK  ---

require 'fileutils'

module MasterFileManagementJobs
  class Move < ActiveJob::Base
    queue_as :master_file_management_move

    # UMD Customization
    def cleanup_empty_source_dir(source)
      sdir = Pathname(source).dirname
      sdir_name = sdir.basename.to_s
      sdir_path_items = sdir.each_filename.to_a
      return unless sdir_path_items.include?('uploads')
      is_second_level_subdir = (sdir_path_items.find_index(sdir_name) - sdir_path_items.find_index('uploads')) > 1
      FileUtils.remove_dir(sdir) if Dir.empty?(sdir) && is_second_level_subdir
    end
    # End UMD Customization

    def perform(id, newpath)
    def perform(id, newpath)
      Rails.logger.debug "Moving masterfile to #{newpath}"

      masterfile = MasterFile.find(id)
      oldpath = masterfile.file_location
      old_locator = FileLocator.new(oldpath)

      if newpath == oldpath
        Rails.logger.info "Masterfile #{newpath} already moved"
      elsif old_locator.exists?
        new_locator = FileLocator.new(newpath)
        FileMover.move(old_locator, new_locator)
        masterfile.file_location = newpath
      	masterfile.save
        # UMD Customization
        cleanup_empty_source_dir(oldpath) if old_locator.uri.scheme == "file"
        # End UMD Customization
        Rails.logger.info "#{oldpath} has been moved to #{newpath}"
      else
        Rails.logger.error "MasterFile #{oldpath} does not exist"
      end
    end
  end

  class Delete < ActiveJob::Base
    queue_as :master_file_management_delete
    def perform(id)
      Rails.logger.debug "Deleting masterfile"

      masterfile = MasterFile.find(id)
      oldpath = masterfile.file_location
      locator = FileLocator.new(oldpath)
      if locator.exists?
        case locator.uri.scheme
        when 'file' then File.delete(oldpath)
        when 's3'   then FileLocator::S3File.new(locator.source).object.delete
        end
      	Rails.logger.info "#{oldpath} has been deleted"
      else
      	Rails.logger.warn "MasterFile #{oldpath} does not exist"
      end
    end
  end
end
