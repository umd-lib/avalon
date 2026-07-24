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

module TranscriptionJobs
  # Structured logging shared by all TranscriptionJobs classes. Every log
  # line carries the same correlation keys so a single transcription_request_id
  # (or provider_job_id) can be grepped across submit/poll/complete/cancel.
  module Logging
    PREFIX = '[TranscriptionJobs]'

    def log_transcription(level, message, request: nil, **extra)
      context = {
        job: self.class.name,
        transcription_request_id: request&.id,
        provider_job_id: request&.provider_job_id,
        master_file_id: request&.master_file_id,
        media_object_id: request&.media_object_id
      }.merge(extra).compact

      formatted_context = context.map { |k, v| "#{k}=#{v}" }.join(' ')
      Rails.logger.public_send(level, "#{PREFIX} #{message} #{formatted_context}".strip)
    end
  end
end
