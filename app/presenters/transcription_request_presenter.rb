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

class TranscriptionRequestPresenter
  attr_reader :transcription_request

  def initialize(transcription_request)
    @transcription_request = transcription_request
  end

  delegate :id, :status, :provider, :language, :master_file_id, :media_object_id,
           :created_at, :submitted_at, :finished_at, :error_message, :active?, :failed?,
           to: :transcription_request

  def master_file_url
    master_file_id.present? ? Rails.application.routes.url_helpers.master_file_path(master_file_id) : ''
  end

  def media_object_url
    media_object_id.present? ? Rails.application.routes.url_helpers.media_object_path(media_object_id) : ''
  end
end
