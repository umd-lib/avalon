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

class TranscriptionRequestsController < ApplicationController
  before_action :set_transcription_request, only: [:show, :retry, :cancel]
  before_action :ensure_transcription_enabled, only: [:create, :create_for_media_object, :retry]
  skip_before_action :verify_authenticity_token, only: [:progress]

  # GET /transcription_requests
  def index
    authorize! :read, :transcription_dashboard
  end

  # GET /transcription_requests/1
  def show
    authorize! :read, :transcription_dashboard
  end

  # POST /transcription_requests/paged_index
  def paged_index
    authorize! :read, :transcription_dashboard

    # TranscriptionRequests for the index page are loaded via
    # /javascript/components/tables/TranscriptionRequestsTable.jsx which
    # requests the json for all records on initial page load.
    @transcription_requests = TranscriptionRequest.all
    records_total = TranscriptionRequest.count

    response = {
      "recordsTotal": records_total,
      "data": @transcription_requests.collect do |transcription_request|
        presenter = TranscriptionRequestPresenter.new(transcription_request)
        [
          "<span data-transcription-request-id=\"#{presenter.id}\" class=\"transcription-request-status\">#{presenter.status}</span>",
          view_context.link_to(presenter.id, transcription_request_path(presenter.id)),
          presenter.provider,
          view_context.link_to(presenter.master_file_id, presenter.master_file_url),
          view_context.link_to(presenter.media_object_id, presenter.media_object_url),
          presenter.created_at.strftime('%Y-%m-%d %H:%M:%S'),
          actions_html(transcription_request)
        ]
      end
    }
    respond_to do |format|
      format.json do
        render json: response
      end
    end
  end

  # POST /transcription_requests/progress
  def progress
    authorize! :read, :transcription_dashboard
    status_data = {}
    TranscriptionRequest.where(id: params[:ids]).each do |transcription_request|
      status_data[transcription_request.id] = { status: transcription_request.status }
    end
    respond_to do |format|
      format.json do
        render json: status_data
      end
    end
  end

  # POST /transcription_requests
  # Enqueues transcription for a single MasterFile section.
  def create
    authorize! :manage, TranscriptionRequest

    transcription_request = TranscriptionRequest.new(
      master_file_id: params[:master_file_id],
      provider: Settings.transcription.default_provider
    )

    if transcription_request.save
      TranscriptionJobs::SubmitTranscriptionRequestJob.perform_later(transcription_request.id)
      redirect_back fallback_location: transcription_requests_path, notice: 'Transcription requested.'
    else
      redirect_back fallback_location: transcription_requests_path, alert: transcription_request.errors.full_messages.to_sentence
    end
  end

  # POST /transcription_requests/create_for_media_object
  # Enqueues transcription for every eligible section of a MediaObject,
  # silently skipping sections that already have a caption/transcript or an
  # active transcription request.
  def create_for_media_object
    authorize! :manage, TranscriptionRequest

    media_object = MediaObject.find(params[:media_object_id])
    media_object.section_ids.each { |master_file_id| enqueue_if_eligible(master_file_id) }

    redirect_back fallback_location: transcription_requests_path, notice: 'Transcription requested for eligible sections.'
  end

  # POST /transcription_requests/1/retry
  # Creates a fresh request for the same master file (only meaningful for a
  # failed request — retrying is just re-submitting a new request, since a
  # completed/cancelled request needs no retry and an active one is already
  # in flight).
  def retry
    authorize! :manage, TranscriptionRequest

    if @transcription_request.failed?
      new_request = TranscriptionRequest.create!(
        master_file_id: @transcription_request.master_file_id,
        provider: @transcription_request.provider,
        language: @transcription_request.language
      )
      TranscriptionJobs::SubmitTranscriptionRequestJob.perform_later(new_request.id)
    end

    redirect_back fallback_location: transcription_requests_path, notice: 'Transcription retried.'
  end

  # POST /transcription_requests/1/cancel
  def cancel
    authorize! :manage, TranscriptionRequest
    TranscriptionJobs::CancelTranscriptionRequestJob.perform_later(@transcription_request.id)
    redirect_back fallback_location: transcription_requests_path, notice: 'Cancellation requested.'
  end

  private

    def set_transcription_request
      @transcription_request = TranscriptionRequest.find(params[:id])
    end

    def ensure_transcription_enabled
      return if Settings.transcription.enabled

      redirect_back fallback_location: transcription_requests_path, alert: 'Transcription is currently disabled.'
    end

    def enqueue_if_eligible(master_file_id)
      return if TranscriptionRequest.active.exists?(master_file_id: master_file_id)
      return unless MasterFile.exists?(master_file_id)

      master_file = MasterFile.find(master_file_id)
      # include_private: true because a pending_review file is tagged
      # 'private' (hidden from the public until approved) and would
      # otherwise be invisible to this check by default. A rejected
      # caption/transcript shouldn't block retrying — otherwise a rejected
      # transcription could never be resubmitted — but pending_review or
      # approved still counts as "already have one."
      return if master_file.supplemental_files(tag: 'caption', include_private: true).reject(&:rejected?).present?
      return if master_file.supplemental_files(tag: 'transcript', include_private: true).reject(&:rejected?).present?

      transcription_request = TranscriptionRequest.new(master_file_id: master_file_id, provider: Settings.transcription.default_provider)
      return unless transcription_request.save

      TranscriptionJobs::SubmitTranscriptionRequestJob.perform_later(transcription_request.id)
    end

    def actions_html(transcription_request)
      buttons = []
      if transcription_request.failed?
        buttons << view_context.link_to('Retry', retry_transcription_request_path(transcription_request),
                                         method: :post, class: 'btn btn-sm btn-outline',
                                         data: { confirm: 'Retry this transcription?' })
      end
      if transcription_request.active?
        buttons << view_context.link_to('Cancel', cancel_transcription_request_path(transcription_request),
                                         method: :post, class: 'btn btn-sm btn-outline',
                                         data: { confirm: 'Cancel this transcription?' })
      end
      buttons << view_context.link_to('Details', transcription_request_path(transcription_request), class: 'btn btn-sm btn-outline')
      buttons.join(' ')
    end
end
