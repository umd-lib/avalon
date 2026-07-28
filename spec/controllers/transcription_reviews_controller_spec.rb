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

    context 'when not administrator' do
      let(:user) { FactoryBot.create(:user) }

      it 'redirects to restricted content page' do
        post :reject, params: { id: pending_file.to_param }, session: valid_session
        expect(response).to render_template('errors/restricted_pid')
      end
    end
  end
end
