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

module TranscriptionProviders
  # Raised when a provider adapter is asked to act on a job it can't process,
  # e.g. a media source it doesn't know how to read.
  class UnsupportedMediaSource < StandardError; end

  # Raised when a provider job is reported complete but no transcript output
  # is available yet to retrieve.
  class TranscriptNotAvailable < StandardError; end

  StatusResult = Struct.new(:status, :raw_response, keyword_init: true)
  TranscriptResult = Struct.new(:transcript_text, :caption_vtt, :raw_response, keyword_init: true)

  # Contract every transcription provider adapter must implement. See
  # AwsTranscribe for the reference implementation.
  class Base
    # Submits master_file's media for transcription. Returns a String
    # provider_job_id that can be used to poll status/fetch results later.
    def submit(master_file:, language: nil)
      raise NotImplementedError
    end

    # Returns a StatusResult with status one of :in_progress, :completed, :failed.
    def fetch_status(provider_job_id)
      raise NotImplementedError
    end

    # Returns a TranscriptResult once the provider job has completed.
    def fetch_transcript(provider_job_id)
      raise NotImplementedError
    end

    # Cancels an in-flight provider job. Best-effort; providers that can't
    # cancel a job in its current state should no-op rather than raise.
    def cancel(provider_job_id)
      raise NotImplementedError
    end
  end
end
