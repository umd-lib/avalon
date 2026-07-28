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
require 'aws-sdk-s3'

module TranscriptionJobs
  # Errors worth retrying automatically (network blips, provider throttling/
  # internal errors) as opposed to permanent failures (unsupported media,
  # unknown provider, validation errors, access/config errors) that will
  # never succeed on retry and should fail the TranscriptionRequest
  # immediately instead.
  #
  # Deliberately narrower than Aws::TranscribeService::Errors::ServiceError /
  # Aws::S3::Errors::ServiceError — those base classes also cover permanent
  # errors (BadRequestException, AccessDenied, NoSuchKey, ...) that would
  # otherwise get misclassified as transient and retried pointlessly.
  TRANSIENT_ERRORS = [
    Seahorse::Client::NetworkingError,
    Aws::TranscribeService::Errors::InternalFailureException,
    Aws::TranscribeService::Errors::LimitExceededException,
    Net::OpenTimeout,
    Net::ReadTimeout,
    Errno::ECONNRESET,
    Errno::ETIMEDOUT
  ].freeze

  # Submits a pending TranscriptionRequest to its provider.
  class SubmitTranscriptionRequestJob < ApplicationJob
    include TranscriptionJobs::Logging

    queue_as :transcription
    retry_on(*TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: 5) do |job, error|
      job.class.fail_after_retries(job.arguments.first, error)
    end

    def perform(transcription_request_id)
      request = TranscriptionRequest.find_by(id: transcription_request_id)
      return if request.nil? || !request.pending?

      provider = TranscriptionProviders::Registry.for(request.provider)
      provider_job_id = provider.submit(master_file: request.master_file, language: request.language)

      request.transition_to!('submitted', provider_job_id: provider_job_id)
    rescue *TRANSIENT_ERRORS => e
      log_transcription(:warn, 'transient error submitting, will retry', request: request, error: "#{e.class}: #{e.message}")
      raise
    rescue StandardError => e
      log_transcription(:error, 'permanent failure submitting', request: request, error: "#{e.class}: #{e.message}")
      request.transition_to!('failed', error_message: e.message) if request && !request.terminal?
    end

    def self.fail_after_retries(transcription_request_id, error)
      request = TranscriptionRequest.find_by(id: transcription_request_id)
      return unless request && !request.terminal?

      Rails.logger.error("[TranscriptionJobs] job=#{name} transcription_request_id=#{transcription_request_id} error=gave up after retries: #{error.class}: #{error.message}")
      request.transition_to!('failed', error_message: "Gave up after retries: #{error.message}")
    end
  end

  # Scheduled sweep (via sidekiq-cron) over active TranscriptionRequests,
  # grouped by provider, checking each one's status and dispatching
  # completion materialization once a provider job finishes.
  class PollTranscriptionRequestsJob < ApplicationJob
    include TranscriptionJobs::Logging

    queue_as :transcription

    def perform
      TranscriptionRequest.active.where.not(provider_job_id: nil).group_by(&:provider).each do |provider_name, requests|
        provider = TranscriptionProviders::Registry.for(provider_name)
        requests.each { |request| poll_one(provider, request) }
      end
    end

    private

    def poll_one(provider, request)
      result = provider.fetch_status(request.provider_job_id)

      case result.status
      when :in_progress
        request.transition_to!('in_progress', raw_response: result.raw_response.to_json) if request.submitted?
      when :completed
        TranscriptionJobs::CompleteTranscriptionRequestJob.perform_later(request.id)
      when :failed
        request.transition_to!('failed', raw_response: result.raw_response.to_json, error_message: 'Provider reported job failure')
      end
    rescue *TRANSIENT_ERRORS => e
      # Cron re-runs every minute, so a transient blip just gets picked up
      # again on the next sweep — no need to fail the request over it.
      log_transcription(:warn, 'transient error polling status, will retry next sweep', request: request, error: "#{e.class}: #{e.message}")
    rescue StandardError => e
      log_transcription(:error, 'permanent failure polling status', request: request, error: "#{e.class}: #{e.message}")
      request.transition_to!('failed', error_message: e.message) unless request.terminal?
    end
  end

  # Downloads/normalizes the finished provider transcript, creates a single
  # SupplementalFile artifact (a .vtt tagged both caption and transcript,
  # falling back to a transcript-only .txt when no VTT is available), and
  # marks the TranscriptionRequest completed.
  class CompleteTranscriptionRequestJob < ApplicationJob
    include TranscriptionJobs::Logging

    queue_as :transcription
    retry_on(*TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: 5) do |job, error|
      job.class.fail_after_retries(job.arguments.first, error)
    end

    def perform(transcription_request_id)
      request = TranscriptionRequest.find_by(id: transcription_request_id)
      return if request.nil? || request.terminal?

      provider = TranscriptionProviders::Registry.for(request.provider)
      result = provider.fetch_transcript(request.provider_job_id)

      created_file = create_supplemental_file(request, result)
      # Registering the file saves the MasterFile, which reindexes it and —
      # via MasterFile's own after_update_index hook — already enqueues
      # MediaObjectIndexingJob for the parent media object. No need to
      # trigger that ourselves too.
      register_supplemental_files(request, [created_file]) if created_file

      # in_review (not completed) when the artifact is gated behind human
      # approval — TranscriptionReviewsController#approve/#reject moves it
      # on to completed/rejected once that happens.
      final_status = created_file&.pending_review? ? 'in_review' : 'completed'
      request.transition_to!(final_status, transcript_text: result.transcript_text, raw_response: result.raw_response.to_json)
    rescue *TRANSIENT_ERRORS => e
      log_transcription(:warn, 'transient error completing, will retry', request: request, error: "#{e.class}: #{e.message}")
      raise
    rescue StandardError => e
      log_transcription(:error, 'permanent failure completing', request: request, error: "#{e.class}: #{e.message}")
      request.transition_to!('failed', error_message: e.message) if request && !request.terminal?
    end

    def self.fail_after_retries(transcription_request_id, error)
      request = TranscriptionRequest.find_by(id: transcription_request_id)
      return unless request && !request.terminal?

      Rails.logger.error("[TranscriptionJobs] job=#{name} transcription_request_id=#{transcription_request_id} error=gave up after retries: #{error.class}: #{error.message}")
      request.transition_to!('failed', error_message: "Gave up after retries: #{error.message}")
    end

    private

    # A single WebVTT file. For video sections it's tagged both 'caption'
    # and 'transcript' — the same "treat as transcript" pattern the Section
    # Files upload UI already supports for manual uploads
    # (SupplementalFile#caption_transcript?) — so there's only ever one file
    # for a reviewer to check or correct, and no risk of the caption and
    # transcript drifting out of sync with each other. For audio-only
    # sections it's tagged 'transcript' only — 'caption' never applies to
    # audio (see MasterFile#is_video?; matches the same gate
    # _file_upload.html.erb already uses to hide the Captions upload UI for
    # audio sections). Either way, the plain-text transcript is derived from
    # this file's cues on demand (Avalon::TranscriptParser, already used by
    # SupplementalFile#segment_transcript for Solr indexing) rather than
    # stored as a second, independently-editable artifact.
    #
    # Falls back to a transcript-only .txt artifact when the provider didn't
    # return a VTT (e.g. subtitle generation isn't supported for the job's
    # language) — see TranscriptionProviders::AwsTranscribe#fetch_transcript,
    # where caption_vtt is nil whenever AWS returns no subtitle_file_uris.
    def create_supplemental_file(request, result)
      if result.caption_vtt.present?
        # 'caption' only applies to video — an audio-only section has no
        # visual track to overlay it on, and (per the same is_video? gate
        # the Section Files upload UI already uses in _file_upload.html.erb)
        # a caption-tagged file on an audio section would end up invisible
        # in the Section Files list entirely, since the Captions partial
        # never renders there and the Transcripts list skips anything
        # already tagged 'caption'.
        tags = request.master_file.is_video? ? %w[caption transcript machine_generated] : %w[transcript machine_generated]
        content = result.caption_vtt
        extension = 'vtt'
        content_type = 'text/vtt'
        label = request.master_file.is_video? ? 'Machine-generated Caption' : 'Machine-generated Transcript'
      elsif result.transcript_text.present?
        tags = %w[transcript machine_generated]
        content = result.transcript_text
        extension = 'txt'
        content_type = 'text/plain'
        label = 'Machine-generated Transcript'
      else
        return nil
      end

      review_required = request.master_file.media_object&.collection&.review_required?
      tags += ['private'] if review_required
      supplemental_file = SupplementalFile.new(
        parent_id: request.master_file_id,
        tags: tags,
        review_status: (review_required ? 'pending_review' : nil),
        language: request.language,
        label: label
      )
      supplemental_file.file.attach(
        io: StringIO.new(content),
        filename: "#{request.master_file_id}_caption.#{extension}",
        content_type: content_type
      )
      supplemental_file.save!
      supplemental_file
    end

    # Creating a SupplementalFile with parent_id set is enough for its own
    # Solr doc/indexing, but MasterFile keeps its own separate list of
    # attached files (supplemental_files_json) that the UI and eligibility
    # checks (e.g. TranscriptionRequestsController#enqueue_if_eligible,
    # the "Transcribe" button's visibility) read from — it isn't derived by
    # querying SupplementalFile.where(parent_id:). Without this, a
    # completed transcription's caption/transcript wouldn't show up on the
    # section or prevent it from being re-transcribed. Same pattern already
    # used for auto-extracted captions in MasterFile#update_progress_on_success!.
    def register_supplemental_files(request, supplemental_files)
      master_file = request.master_file
      master_file.add_supplemental_files(supplemental_files.map { |sf| sf.to_global_id.to_s })
      master_file.save!
    end
  end

  # Best-effort cancellation: asks the provider to cancel the in-flight job
  # (if one was ever submitted), then marks the request cancelled locally
  # regardless of whether the provider-side cancel succeeded.
  class CancelTranscriptionRequestJob < ApplicationJob
    include TranscriptionJobs::Logging

    queue_as :transcription

    def perform(transcription_request_id)
      request = TranscriptionRequest.find_by(id: transcription_request_id)
      return if request.nil? || request.terminal?

      if request.provider_job_id.present?
        begin
          TranscriptionProviders::Registry.for(request.provider).cancel(request.provider_job_id)
        rescue StandardError => e
          log_transcription(:warn, 'provider cancel failed, cancelling locally anyway', request: request, error: "#{e.class}: #{e.message}")
        end
      end

      request.transition_to!('cancelled')
    end
  end
end
