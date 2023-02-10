# Copyright 2011-2022, The Trustees of Indiana University and Northwestern
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

module MasterFileBuilder
  class BuildError < Exception; end
  Spec = Struct.new(:content, :original_filename, :content_type, :workflow, :file_size, :auth_header)

  def self.build(media_object, params)
    builder = if params.has_key?(:Filedata) and params.has_key?(:original)
      FileUpload
    elsif params.has_key?(:selected_files)
      DropboxUpload
    else
      nil
    end
    if builder.nil?
      { flash: { error: ["You must specify a file to upload"] }, master_files: [] }
    else
      from_specs(media_object, builder.build(params))
    end
  end

  def self.from_specs(media_object, specs)
    response = { flash: { error: [] }, master_files: [] }
    specs.each do |spec|
      unless spec.original_filename.valid_encoding? && spec.original_filename.ascii_only?
        raise BuildError, 'The file you have uploaded has non-ASCII characters in its name.'
      end

      # Start LIBAVALON-128, LIBAVALON-286
      collection_path = media_object.collection.dropbox_absolute_path
      original_filename = spec.content.respond_to?("original_filename") ? spec.content.original_filename : spec.original_filename;
      desination_path = File.join(collection_path, 'uploads', DateTime.now.strftime("%Y%m%d"), DateTime.now.strftime("%H%M%S%L"), original_filename)
      if (File.exists?(desination_path))
        response[:flash][:error] << "Duplicate file. File already exists at path #{desination_path}!"
        next
      end
      content = spec.content
      FileUtils.mkdir_p(File.dirname(desination_path))
      # if uploaded file, move from /tmp dir to collection dir in masterfiles volume.
      if content.is_a? ActionDispatch::Http::UploadedFile
        FileUtils.mv(content.path, desination_path)
        content = Addressable::URI.join('file:///', desination_path)
      # else, if Google drive file, copy to the local dropbox upload dir before processing -- the authorization 
      # header is not available to the post processing move task, and therefore, it is unable to move/copy the
      # file from the google drive to the archive directory to make it available for downloads.
      elsif content.to_s.starts_with?('https://www.googleapis.com')
        IO.copy_stream(URI.open(content, spec.auth_header), desination_path)
        content = Addressable::URI.join('file:///', desination_path)
      end
      
      master_file = MasterFile.new()
      master_file.setContent(content, file_name: spec.original_filename, file_size: spec.file_size, auth_header: nil, dropbox_dir: media_object.collection.dropbox_absolute_path)
      master_file.set_workflow(spec.workflow)
      # End LIBAVALON-128, LIBAVALON-286

      if 'Unknown' == master_file.file_format
        response[:flash][:error] << "The file was not recognized as audio or video - %s (%s)" % [spec.original_filename, spec.content_type]
        master_file.destroy
        next
      else
        response[:flash][:notice] = create_upload_notice(master_file.file_format)
      end

      master_file.media_object = media_object
      if master_file.save
        media_object.save
        master_file.process
        response[:master_files] << master_file
      else
        response[:flash][:error] << "There was a problem storing the file"
      end
    end
    response[:flash][:error] = nil if response[:flash][:error].empty?
    response
  end

  def self.create_upload_notice(format)
    case format
    when /^Sound$/
     'The uploaded content appears to be audio';
    when /^Moving image$/
     'The uploaded content appears to be video';
    else
     'The uploaded content could not be identified';
    end
  end

  module FileUpload
    def self.build(params)
      params[:Filedata].collect do |file|
        if (file.size > MasterFile::MAXIMUM_UPLOAD_SIZE)
          raise BuildError, "The file you have uploaded is too large"
        end
        Spec.new(file, file.original_filename, file.content_type, params[:workflow])
      end
    end
  end

  module DropboxUpload
    def self.build(params)
      params.require(:selected_files).permit!.values.collect do |entry|
        uri = Addressable::URI.parse(entry[:url])
        path = entry["file_name"] || Addressable::URI.unencode(uri.path)
        Spec.new(uri, File.basename(path), Rack::Mime.mime_type(File.extname(path)), params[:workflow], entry["file_size"], entry["auth_header"]&.to_h)
      end
    end
  end
end
