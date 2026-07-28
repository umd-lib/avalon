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

require 'rails_helper'
require 'avalon/webvtt_cue_editor'

RSpec.describe TranscriptionReviewsController, type: :controller do
  let(:valid_session) { {} }
  let(:user) { FactoryBot.create(:administrator) }
  let(:master_file) { FactoryBot.create(:master_file, :with_media_object) }
  let(:pending_file) do
    FactoryBot.create(:supplemental_file, :with_caption_file,
                       parent_id: master_file.id,
                       tags: ['caption', 'transcript', 'machine_generated', 'private'],
                       review_status: 'pending_review')
  end

  before { sign_in user }

  describe 'GET #index' do
    it 'returns a success response' do
      get :index, params: {}, session: valid_session
      expect(response).to be_successful
    end

    context 'when not administrator' do
      let(:user) { FactoryBot.create(:user) }

      it 'redirects to restricted content page' do
        get :index, params: {}, session: valid_session
        expect(response).to render_template('errors/restricted_pid')
      end
    end
  end

  describe 'POST #paged_index' do
    before { pending_file }

    it 'returns only pending_review files' do
      approved_file = FactoryBot.create(:supplemental_file, :with_caption_file, review_status: 'approved')

      post :paged_index, format: 'json', session: valid_session
      parsed_response = JSON.parse(response.body)

      expect(parsed_response['recordsTotal']).to eq(1)
      expect(parsed_response['data'].count).to eq(1)
      expect(approved_file.review_status).to eq('approved')
    end
  end

  describe 'POST #approve' do
    it 'approves the file and enqueues a reindex' do
      # MediaObjectIndexingJob uses activejob-uniqueness, whose Redis lock
      # persists across specs in this suite — have_enqueued_job can flake
      # for it, so assert via a message expectation instead (see CLAUDE.md).
      expect(MediaObjectIndexingJob).to receive(:perform_later).with(master_file.media_object_id)

      post :approve, params: { id: pending_file.to_param }, session: valid_session

      expect(pending_file.reload.review_status).to eq('approved')
      expect(pending_file.reload.tags).not_to include('private')
      expect(response).to redirect_to(transcription_reviews_path)
    end

    it 'transitions the transcription request that produced the file from in_review to completed' do
      request = TranscriptionRequest.create!(master_file_id: master_file.id, provider: 'aws_transcribe')
      request.transition_to!('submitted')
      request.transition_to!('in_progress')
      request.transition_to!('in_review')
      pending_file

      post :approve, params: { id: pending_file.to_param }, session: valid_session

      expect(request.reload.status).to eq('completed')
    end

    context 'when not administrator' do
      let(:user) { FactoryBot.create(:user) }

      it 'redirects to restricted content page' do
        post :approve, params: { id: pending_file.to_param }, session: valid_session
        expect(response).to render_template('errors/restricted_pid')
      end
    end
  end

  describe 'POST #reject' do
    it 'rejects the file without reindexing' do
      # Force pending_file (and its MediaObject, via master_file) to be
      # created before the message expectation is installed below —
      # MediaObject's own after-create indexing hook enqueues
      # MediaObjectIndexingJob too, which would otherwise be misattributed
      # to the reject action itself.
      id = pending_file.to_param

      expect(MediaObjectIndexingJob).not_to receive(:perform_later)

      post :reject, params: { id: id }, session: valid_session

      expect(pending_file.reload.review_status).to eq('rejected')
      expect(pending_file.reload.tags).to include('private')
      expect(response).to redirect_to(transcription_reviews_path)
    end

    it 'transitions the transcription request that produced the file from in_review to rejected' do
      request = TranscriptionRequest.create!(master_file_id: master_file.id, provider: 'aws_transcribe')
      request.transition_to!('submitted')
      request.transition_to!('in_progress')
      request.transition_to!('in_review')
      id = pending_file.to_param

      post :reject, params: { id: id }, session: valid_session

      expect(request.reload.status).to eq('rejected')
    end

    context 'when not administrator' do
      let(:user) { FactoryBot.create(:user) }

      it 'redirects to restricted content page' do
        post :reject, params: { id: pending_file.to_param }, session: valid_session
        expect(response).to render_template('errors/restricted_pid')
      end
    end
  end

  describe 'GET #edit' do
    it 'returns a success response for a pending-review caption file' do
      get :edit, params: { id: pending_file.to_param }, session: valid_session
      expect(response).to be_successful
    end

    it 'redirects with an alert for a pending-review file with no caption tag (the transcript-only fallback case)' do
      transcript_only_file = FactoryBot.create(:supplemental_file, :with_transcript_file,
                                                 parent_id: master_file.id,
                                                 tags: ['transcript', 'machine_generated', 'private'],
                                                 review_status: 'pending_review')

      get :edit, params: { id: transcript_only_file.to_param }, session: valid_session
      expect(response).to redirect_to(transcription_reviews_path)
      expect(flash[:alert]).to be_present
    end

    it 'redirects with an alert for a file that is not pending_review' do
      pending_file.approve!('someone')

      get :edit, params: { id: pending_file.to_param }, session: valid_session
      expect(response).to redirect_to(transcription_reviews_path)
      expect(flash[:alert]).to be_present
    end

    context 'when not administrator' do
      let(:user) { FactoryBot.create(:user) }

      it 'redirects to restricted content page' do
        get :edit, params: { id: pending_file.to_param }, session: valid_session
        expect(response).to render_template('errors/restricted_pid')
      end
    end
  end

  describe 'POST #update_text' do
    it 'persists the edited cue text into the same record' do
      cue_index = Avalon::WebvttCueEditor.new(pending_file.file.download).cues.first.index

      post :update_text, params: { id: pending_file.to_param, cues: { cue_index => 'Corrected text' } }, session: valid_session

      pending_file.reload
      expect(pending_file.file.download).to include('Corrected text')
      expect(pending_file.review_status).to eq('pending_review')
      expect(pending_file.tags).to include('private')
      expect(response).to redirect_to(transcription_reviews_path)
    end

    it 'redirects back to the edit page with an alert when the cue index is unknown' do
      post :update_text, params: { id: pending_file.to_param, cues: { 999 => 'no such cue' } }, session: valid_session

      expect(response).to redirect_to(edit_transcription_review_path(pending_file))
      expect(flash[:alert]).to be_present
    end

    it 'does not modify a file that is not pending_review' do
      pending_file.approve!('someone')
      original_content = pending_file.file.download

      post :update_text, params: { id: pending_file.to_param, cues: { 0 => 'Corrected text' } }, session: valid_session

      expect(response).to redirect_to(transcription_reviews_path)
      expect(pending_file.reload.file.download).to eq(original_content)
    end

    context 'when not administrator' do
      let(:user) { FactoryBot.create(:user) }

      it 'redirects to restricted content page' do
        post :update_text, params: { id: pending_file.to_param, cues: { 0 => 'x' } }, session: valid_session
        expect(response).to render_template('errors/restricted_pid')
      end
    end
  end
end
