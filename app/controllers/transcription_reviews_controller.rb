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

class TranscriptionReviewsController < ApplicationController
  before_action :set_supplemental_file, only: [:approve, :reject]

  # GET /transcription_reviews
  def index
    authorize! :read, :transcription_review_dashboard
  end

  # POST /transcription_reviews/paged_index
  def paged_index
    authorize! :read, :transcription_review_dashboard

    # Pending-review SupplementalFiles for the index page are loaded via
    # /javascript/components/tables/TranscriptionReviewsTable.jsx which
    # requests the json for all records on initial page load.
    @supplemental_files = SupplementalFile.where(review_status: 'pending_review')
    records_total = @supplemental_files.count

    response = {
      "recordsTotal": records_total,
      "data": @supplemental_files.collect do |supplemental_file|
        presenter = TranscriptionReviewPresenter.new(supplemental_file)
        [
          presenter.type,
          presenter.id,
          view_context.link_to(presenter.master_file_id, presenter.master_file_url),
          view_context.link_to(presenter.media_object_id, presenter.media_object_url),
          presenter.language,
          presenter.created_at.strftime('%Y-%m-%d %H:%M:%S'),
          actions_html(supplemental_file, presenter)
        ]
      end
    }
    respond_to do |format|
      format.json do
        render json: response
      end
    end
  end

  # POST /transcription_reviews/1/approve
  def approve
    authorize! :manage, :transcription_review

    @supplemental_file.approve!(current_user.user_key)
    media_object_id = @supplemental_file.master_file&.media_object_id
    MediaObjectIndexingJob.perform_later(media_object_id) if media_object_id.present?

    redirect_back fallback_location: transcription_reviews_path, notice: 'Approved.'
  end

  # POST /transcription_reviews/1/reject
  def reject
    authorize! :manage, :transcription_review

    @supplemental_file.reject!(current_user.user_key)

    redirect_back fallback_location: transcription_reviews_path, notice: 'Rejected.'
  end

  private

    def set_supplemental_file
      @supplemental_file = SupplementalFile.find(params[:id])
    end

    def actions_html(supplemental_file, presenter)
      buttons = []
      buttons << view_context.link_to('Approve', approve_transcription_review_path(supplemental_file),
                                       method: :post, class: 'btn btn-sm btn-outline',
                                       data: { confirm: 'Approve this caption/transcript?' })
      buttons << view_context.link_to('Reject', reject_transcription_review_path(supplemental_file),
                                       method: :post, class: 'btn btn-sm btn-outline',
                                       data: { confirm: 'Reject this caption/transcript?' })
      buttons << view_context.link_to('Replace', presenter.replace_url, class: 'btn btn-sm btn-outline')
      buttons.join(' ')
    end
end
