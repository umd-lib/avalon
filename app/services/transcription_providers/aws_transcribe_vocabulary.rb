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

require 'aws-sdk-transcribeservice'

module TranscriptionProviders
  # Manages AWS Transcribe custom vocabularies (a reusable resource, not a
  # per-item transcription job) on behalf of TranscriptionVocabulary records.
  # Deliberately not a TranscriptionProviders::Base subclass/Registry entry —
  # that contract models a single transcription job's lifecycle, which this
  # isn't.
  class AwsTranscribeVocabulary
    StateResult = Struct.new(:state, :failure_reason, keyword_init: true)

    def initialize(client: Aws::TranscribeService::Client.new)
      @client = client
    end

    # Creates the vocabulary in AWS on first sync, updates it on every
    # subsequent sync. Both calls only kick off AWS-side async processing —
    # the resulting VocabularyState is PENDING until a later fetch_state
    # poll observes READY/FAILED.
    def create_or_update(vocabulary)
      params = {
        vocabulary_name: vocabulary.aws_vocabulary_name,
        language_code: TranscriptionProviders::AwsTranscribe::LANGUAGE_CODE_MAP.fetch(vocabulary.language),
        phrases: vocabulary.phrase_list
      }

      if vocabulary.last_synced_at.nil?
        @client.create_vocabulary(**params)
      else
        @client.update_vocabulary(**params)
      end
    end

    def fetch_state(aws_vocabulary_name)
      resp = @client.get_vocabulary(vocabulary_name: aws_vocabulary_name)
      state = case resp.vocabulary_state
              when 'READY' then :ready
              when 'FAILED' then :failed
              else :pending
              end

      StateResult.new(state: state, failure_reason: resp.failure_reason)
    end

    def delete(aws_vocabulary_name)
      @client.delete_vocabulary(vocabulary_name: aws_vocabulary_name)
    end
  end
end
