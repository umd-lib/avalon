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

module TranscriptionVocabularyJobs
  TRANSIENT_ERRORS = [
    Seahorse::Client::NetworkingError,
    Aws::TranscribeService::Errors::InternalFailureException,
    Aws::TranscribeService::Errors::LimitExceededException,
    Net::OpenTimeout,
    Net::ReadTimeout,
    Errno::ECONNRESET,
    Errno::ETIMEDOUT
  ].freeze

  # Pushes a TranscriptionVocabulary's current phrases to AWS via
  # Create/UpdateVocabulary (creates on first sync, updates thereafter).
  # This only kicks off AWS-side async processing — PollVocabulariesJob is
  # what later observes READY/FAILED.
  class SyncVocabularyJob < ApplicationJob
    include TranscriptionVocabularyJobs::Logging

    queue_as :transcription
    retry_on(*TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: 5) do |job, error|
      job.class.fail_after_retries(job.arguments.first, error)
    end

    def perform(transcription_vocabulary_id)
      vocabulary = TranscriptionVocabulary.find_by(id: transcription_vocabulary_id)
      return if vocabulary.nil?

      TranscriptionProviders::AwsTranscribeVocabulary.new.create_or_update(vocabulary)
      vocabulary.update!(last_synced_at: Time.current, state: 'pending', error_message: nil)
    rescue *TRANSIENT_ERRORS => e
      log_vocabulary(:warn, 'transient error syncing, will retry', vocabulary: vocabulary, error: "#{e.class}: #{e.message}")
      raise
    rescue StandardError => e
      log_vocabulary(:error, 'permanent failure syncing', vocabulary: vocabulary, error: "#{e.class}: #{e.message}")
      vocabulary&.update(state: 'failed', error_message: e.message)
    end

    def self.fail_after_retries(transcription_vocabulary_id, error)
      vocabulary = TranscriptionVocabulary.find_by(id: transcription_vocabulary_id)
      return unless vocabulary

      Rails.logger.error("[TranscriptionVocabularyJobs] job=#{name} transcription_vocabulary_id=#{transcription_vocabulary_id} error=gave up after retries: #{error.class}: #{error.message}")
      vocabulary.update(state: 'failed', error_message: "Gave up after retries: #{error.message}")
    end
  end

  # Scheduled sweep (via sidekiq-cron) over pending TranscriptionVocabularies,
  # checking AWS's GetVocabulary state until it lands on READY/FAILED.
  class PollVocabulariesJob < ApplicationJob
    include TranscriptionVocabularyJobs::Logging

    queue_as :transcription

    def perform
      TranscriptionVocabulary.pending.each { |vocabulary| poll_one(vocabulary) }
    end

    private

    def poll_one(vocabulary)
      result = TranscriptionProviders::AwsTranscribeVocabulary.new.fetch_state(vocabulary.aws_vocabulary_name)

      case result.state
      when :ready
        vocabulary.update!(state: 'ready', error_message: nil)
      when :failed
        vocabulary.update!(state: 'failed', error_message: result.failure_reason)
      end
    rescue *TRANSIENT_ERRORS => e
      # Cron re-runs every minute, so a transient blip just gets picked up
      # again on the next sweep — no need to fail the vocabulary over it.
      log_vocabulary(:warn, 'transient error polling state, will retry next sweep', vocabulary: vocabulary, error: "#{e.class}: #{e.message}")
    rescue StandardError => e
      log_vocabulary(:error, 'permanent failure polling state', vocabulary: vocabulary, error: "#{e.class}: #{e.message}")
      vocabulary.update(state: 'failed', error_message: e.message)
    end
  end

  # Best-effort deletion: asks AWS to delete the vocabulary, then destroys
  # the local record regardless of whether the provider-side delete
  # succeeded — mirrors CancelTranscriptionRequestJob's precedent.
  class DeleteVocabularyJob < ApplicationJob
    include TranscriptionVocabularyJobs::Logging

    queue_as :transcription

    def perform(transcription_vocabulary_id)
      vocabulary = TranscriptionVocabulary.find_by(id: transcription_vocabulary_id)
      return if vocabulary.nil?

      begin
        TranscriptionProviders::AwsTranscribeVocabulary.new.delete(vocabulary.aws_vocabulary_name)
      rescue StandardError => e
        log_vocabulary(:warn, 'provider delete failed, deleting locally anyway', vocabulary: vocabulary, error: "#{e.class}: #{e.message}")
      end

      vocabulary.destroy
    end
  end
end
