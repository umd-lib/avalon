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
    authorize! :edit, master_file_for(@transcription_request)&.media_object
  end

  # POST /transcription_requests/paged_index
  def paged_index
    authorize! :read, :transcription_dashboard

    # TranscriptionRequests for the index page are loaded via
    # /javascript/components/tables/TranscriptionRequestsTable.jsx which
    # requests the json for all records on initial page load. Grouping by
    # media_object_id (already denormalized onto TranscriptionRequest at
    # creation) means an item with several retried requests only needs one
    # can?(:edit, media_object) check instead of one per row — the real,
    # item-scoped visibility boundary; an administrator's check is always
    # true (can :manage, :all) so this doesn't change what admins see.
    @transcription_requests = TranscriptionRequest.all.group_by(&:media_object_id).flat_map do |media_object_id, requests|
      media_object = media_object_id.present? ? fetch_proxy(media_object_id) : nil
      can?(:edit, media_object) ? requests : []
    end
    records_total = @transcription_requests.count

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
    # Filtered the same way as paged_index — defense in depth, so a manager
    # can't probe the status of requests outside their collections just by
    # passing arbitrary ids directly to this endpoint.
    TranscriptionRequest.where(id: params[:ids]).select { |tr| can?(:edit, master_file_for(tr)&.media_object) }.each do |transcription_request|
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
    authorize! :edit, MasterFile.exists?(params[:master_file_id]) ? MasterFile.find(params[:master_file_id]) : nil

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
    media_object = MediaObject.find(params[:media_object_id])
    authorize! :edit, media_object
    media_object.section_ids.each { |master_file_id| enqueue_if_eligible(master_file_id) }

    redirect_back fallback_location: transcription_requests_path, notice: 'Transcription requested for eligible sections.'
  end

  # POST /transcription_requests/1/retry
  # Creates a fresh request for the same master file (only meaningful for a
  # failed request — retrying is just re-submitting a new request, since a
  # completed/cancelled request needs no retry and an active one is already
  # in flight).
  def retry
    authorize! :edit, master_file_for(@transcription_request)&.media_object

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
    authorize! :edit, master_file_for(@transcription_request)&.media_object
    TranscriptionJobs::CancelTranscriptionRequestJob.perform_later(@transcription_request.id)
    redirect_back fallback_location: transcription_requests_path, notice: 'Cancellation requested.'
  end

  private

    def set_transcription_request
      @transcription_request = TranscriptionRequest.find(params[:id])
    end

    # Guards against MasterFile.find raising on a dangling/blank
    # master_file_id (e.g. an orphaned record) — authorize!/can? against a
    # nil subject falls through to "false for non-admins, true for admins"
    # since no :edit, MasterFile rule matches a non-MasterFile subject.
    def master_file_for(transcription_request)
      return nil unless transcription_request.master_file_id.present? && MasterFile.exists?(transcription_request.master_file_id)

      MasterFile.find(transcription_request.master_file_id)
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
