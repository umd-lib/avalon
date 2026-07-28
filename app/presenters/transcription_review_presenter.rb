# Copyright 2011-2026, The Trustees of Indiana University and Northwestern
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

class TranscriptionReviewPresenter
  attr_reader :supplemental_file

  def initialize(supplemental_file)
    @supplemental_file = supplemental_file
  end

  delegate :id, :created_at, to: :supplemental_file

  def type
    if supplemental_file.caption? && supplemental_file.transcript?
      'caption + transcript'
    elsif supplemental_file.caption?
      'caption'
    else
      'transcript'
    end
  end

  def language
    LanguageTerm.find(supplemental_file.language)&.text || supplemental_file.language
  end

  def master_file_id
    supplemental_file.parent_id
  end

  def media_object_id
    supplemental_file.master_file&.media_object_id
  end

  def master_file_url
    Rails.application.routes.url_helpers.master_file_path(master_file_id)
  end

  def editable?
    supplemental_file.editable_transcription_review?
  end

  def edit_url
    Rails.application.routes.url_helpers.edit_transcription_review_path(supplemental_file.id)
  end

  def media_object_url
    media_object_id.present? ? Rails.application.routes.url_helpers.media_object_path(media_object_id) : ''
  end

  # Where a reviewer goes to reject-and-replace: the existing Section Files
  # upload step on the item's edit page, not a new editor.
  def replace_url
    media_object_id.present? ? Rails.application.routes.url_helpers.edit_media_object_path(media_object_id, step: 'file-upload') : ''
  end
end
