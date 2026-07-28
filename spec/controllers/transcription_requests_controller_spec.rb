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

RSpec.describe TranscriptionRequestsController, type: :controller do
  let(:valid_session) { {} }
  let(:user) { FactoryBot.create(:administrator) }
  let(:master_file) { FactoryBot.create(:master_file, :with_media_object) }
  let(:collection) { master_file.media_object.collection }
  let(:manager) { User.find_by(username: collection.managers.first) }
  let(:editor) { User.find_by(username: collection.editors.first) }
  let(:transcription_request) { TranscriptionRequest.create!(master_file_id: master_file.id, provider: 'aws_transcribe') }

  before do
    sign_in user
    allow(Settings.transcription).to receive(:enabled).and_return(true)
  end

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

    context 'when a collection manager (member of at least one collection)' do
      let(:user) { manager }

      it 'returns a success response' do
        get :index, params: {}, session: valid_session
        expect(response).to be_successful
      end
    end
  end

  describe 'GET #show' do
    it 'returns a success response' do
      get :show, params: { id: transcription_request.to_param }, session: valid_session
      expect(response).to be_successful
    end

    context 'when not administrator' do
      let(:user) { FactoryBot.create(:user) }

      it 'redirects to restricted content page' do
        get :show, params: { id: transcription_request.to_param }, session: valid_session
        expect(response).to render_template('errors/restricted_pid')
      end
    end

    context "when the manager of the request's own collection" do
      let(:user) { manager }

      it 'returns a success response' do
        get :show, params: { id: transcription_request.to_param }, session: valid_session
        expect(response).to be_successful
      end
    end

    context 'when a manager of a different collection' do
      let(:user) { User.find_by(username: FactoryBot.create(:media_object).collection.managers.first) }

      it 'redirects to restricted content page' do
        get :show, params: { id: transcription_request.to_param }, session: valid_session
        expect(response).to render_template('errors/restricted_pid')
      end
    end
  end

  describe 'POST #paged_index' do
    before { transcription_request }

    it 'returns all results for an administrator' do
      post :paged_index, format: 'json', session: valid_session
      parsed_response = JSON.parse(response.body)
      expect(parsed_response['recordsTotal']).to eq(1)
      expect(parsed_response['data'].count).to eq(1)
    end

    context 'when a manager of the request\'s own collection' do
      let(:user) { manager }

      it 'returns the request' do
        post :paged_index, format: 'json', session: valid_session
        parsed_response = JSON.parse(response.body)
        expect(parsed_response['recordsTotal']).to eq(1)
      end
    end

    context 'when a manager of a different collection' do
      let(:user) { User.find_by(username: FactoryBot.create(:media_object).collection.managers.first) }

      it 'does not include the other collection\'s request' do
        post :paged_index, format: 'json', session: valid_session
        parsed_response = JSON.parse(response.body)
        expect(parsed_response['recordsTotal']).to eq(0)
        expect(parsed_response['data']).to be_empty
      end
    end
  end

  describe 'POST #progress' do
    it 'returns JSON with status information' do
      post :progress, format: :json, params: { ids: [transcription_request.id] }, session: valid_session
      expect(response).to be_successful
      expect(JSON.parse(response.body)).to eq({ transcription_request.id.to_s => { 'status' => transcription_request.status } })
    end

    context 'when not administrator' do
      let(:user) { FactoryBot.create(:user) }

      it 'returns unauthorized for JSON requests' do
        post :progress, format: :json, params: { ids: [transcription_request.id] }, session: valid_session
        expect(response).to be_unauthorized
      end
    end

    context 'when a manager of a different collection' do
      let(:user) { User.find_by(username: FactoryBot.create(:media_object).collection.managers.first) }

      it 'does not report status for the other collection\'s request' do
        post :progress, format: :json, params: { ids: [transcription_request.id] }, session: valid_session
        expect(response).to be_successful
        expect(JSON.parse(response.body)).to eq({})
      end
    end
  end

  describe 'POST #create' do
    it 'creates a TranscriptionRequest and enqueues submission' do
      expect do
        post :create, params: { master_file_id: master_file.id }, session: valid_session
      end.to have_enqueued_job(TranscriptionJobs::SubmitTranscriptionRequestJob)

      expect(TranscriptionRequest.where(master_file_id: master_file.id)).to exist
      expect(response).to redirect_to(transcription_requests_path)
    end

    it 'redirects with an alert when the request is invalid' do
      post :create, params: { master_file_id: 'nonexistent' }, session: valid_session
      expect(flash[:alert]).to be_present
      expect(TranscriptionRequest.where(master_file_id: 'nonexistent')).not_to exist
    end

    context 'when not administrator' do
      let(:user) { FactoryBot.create(:user) }

      it 'redirects to restricted content page' do
        post :create, params: { master_file_id: master_file.id }, session: valid_session
        expect(response).to render_template('errors/restricted_pid')
      end
    end

    context 'when a manager of the master file\'s own collection' do
      let(:user) { manager }

      it 'creates a TranscriptionRequest' do
        post :create, params: { master_file_id: master_file.id }, session: valid_session
        expect(TranscriptionRequest.where(master_file_id: master_file.id)).to exist
      end
    end

    context 'when an editor of the master file\'s own collection' do
      let(:user) { editor }

      it 'creates a TranscriptionRequest' do
        post :create, params: { master_file_id: master_file.id }, session: valid_session
        expect(TranscriptionRequest.where(master_file_id: master_file.id)).to exist
      end
    end

    context 'when a manager of a different collection' do
      let(:user) { User.find_by(username: FactoryBot.create(:media_object).collection.managers.first) }

      it 'redirects to restricted content page' do
        post :create, params: { master_file_id: master_file.id }, session: valid_session
        expect(response).to render_template('errors/restricted_pid')
        expect(TranscriptionRequest.where(master_file_id: master_file.id)).not_to exist
      end
    end

    context 'when transcription is disabled' do
      before { allow(Settings.transcription).to receive(:enabled).and_return(false) }

      it 'redirects with an alert and does not create a TranscriptionRequest' do
        post :create, params: { master_file_id: master_file.id }, session: valid_session

        expect(flash[:alert]).to eq('Transcription is currently disabled.')
        expect(TranscriptionRequest.where(master_file_id: master_file.id)).not_to exist
      end
    end
  end

  describe 'POST #retry' do
    context 'when the request has failed' do
      before { transcription_request.update!(status: 'failed', error_message: 'boom') }

      it 'creates a new TranscriptionRequest and enqueues submission' do
        expect do
          post :retry, params: { id: transcription_request.to_param }, session: valid_session
        end.to have_enqueued_job(TranscriptionJobs::SubmitTranscriptionRequestJob)

        expect(TranscriptionRequest.where(master_file_id: master_file.id).count).to eq(2)
      end

      context 'when a manager of the request\'s own collection' do
        let(:user) { manager }

        it 'creates a new TranscriptionRequest' do
          post :retry, params: { id: transcription_request.to_param }, session: valid_session
          expect(TranscriptionRequest.where(master_file_id: master_file.id).count).to eq(2)
        end
      end

      context 'when a manager of a different collection' do
        let(:user) { User.find_by(username: FactoryBot.create(:media_object).collection.managers.first) }

        it 'redirects to restricted content page' do
          post :retry, params: { id: transcription_request.to_param }, session: valid_session
          expect(response).to render_template('errors/restricted_pid')
          expect(TranscriptionRequest.where(master_file_id: master_file.id).count).to eq(1)
        end
      end

      context 'when transcription is disabled' do
        before { allow(Settings.transcription).to receive(:enabled).and_return(false) }

        it 'does not create a new TranscriptionRequest' do
          expect do
            post :retry, params: { id: transcription_request.to_param }, session: valid_session
          end.not_to have_enqueued_job(TranscriptionJobs::SubmitTranscriptionRequestJob)

          expect(TranscriptionRequest.where(master_file_id: master_file.id).count).to eq(1)
        end
      end
    end

    context 'when the request is not failed' do
      it 'does not create a new TranscriptionRequest' do
        expect do
          post :retry, params: { id: transcription_request.to_param }, session: valid_session
        end.not_to have_enqueued_job(TranscriptionJobs::SubmitTranscriptionRequestJob)

        expect(TranscriptionRequest.where(master_file_id: master_file.id).count).to eq(1)
      end
    end
  end

  describe 'POST #cancel' do
    it 'enqueues a CancelTranscriptionRequestJob' do
      expect do
        post :cancel, params: { id: transcription_request.to_param }, session: valid_session
      end.to have_enqueued_job(TranscriptionJobs::CancelTranscriptionRequestJob).with(transcription_request.id)
    end

    context 'when not administrator' do
      let(:user) { FactoryBot.create(:user) }

      it 'redirects to restricted content page' do
        post :cancel, params: { id: transcription_request.to_param }, session: valid_session
        expect(response).to render_template('errors/restricted_pid')
      end
    end

    context 'when an editor of the request\'s own collection' do
      let(:user) { editor }

      it 'enqueues a CancelTranscriptionRequestJob' do
        expect do
          post :cancel, params: { id: transcription_request.to_param }, session: valid_session
        end.to have_enqueued_job(TranscriptionJobs::CancelTranscriptionRequestJob).with(transcription_request.id)
      end
    end

    context 'when a manager of a different collection' do
      let(:user) { User.find_by(username: FactoryBot.create(:media_object).collection.managers.first) }

      it 'redirects to restricted content page' do
        post :cancel, params: { id: transcription_request.to_param }, session: valid_session
        expect(response).to render_template('errors/restricted_pid')
      end
    end
  end

  describe 'POST #create_for_media_object' do
    let(:media_object) { FactoryBot.create(:media_object) }
    let(:eligible_master_file) { FactoryBot.create(:master_file, :with_media_object, media_object: media_object) }
    let(:already_captioned_master_file) { FactoryBot.create(:master_file, :with_media_object, media_object: media_object) }

    before do
      allow(already_captioned_master_file).to receive(:supplemental_files).with(tag: 'caption', include_private: true).and_return([instance_double(SupplementalFile, rejected?: false)])
      allow(MasterFile).to receive(:find).and_call_original
      allow(MasterFile).to receive(:find).with(already_captioned_master_file.id).and_return(already_captioned_master_file)

      media_object.section_ids = [eligible_master_file.id, already_captioned_master_file.id]
      media_object.save!
    end

    it 'enqueues transcription only for eligible sections' do
      post :create_for_media_object, params: { media_object_id: media_object.id }, session: valid_session

      expect(TranscriptionRequest.where(master_file_id: eligible_master_file.id)).to exist
      expect(TranscriptionRequest.where(master_file_id: already_captioned_master_file.id)).not_to exist
    end

    context 'when the existing caption was rejected' do
      before do
        allow(already_captioned_master_file).to receive(:supplemental_files).with(tag: 'caption', include_private: true).and_return([instance_double(SupplementalFile, rejected?: true)])
        allow(already_captioned_master_file).to receive(:supplemental_files).with(tag: 'transcript', include_private: true).and_return([])
      end

      it 'still enqueues transcription for that section' do
        post :create_for_media_object, params: { media_object_id: media_object.id }, session: valid_session
        expect(TranscriptionRequest.where(master_file_id: already_captioned_master_file.id)).to exist
      end
    end

    context 'when not administrator' do
      let(:user) { FactoryBot.create(:user) }

      it 'redirects to restricted content page' do
        post :create_for_media_object, params: { media_object_id: media_object.id }, session: valid_session
        expect(response).to render_template('errors/restricted_pid')
      end
    end

    context 'when a manager of the media object\'s own collection' do
      let(:user) { User.find_by(username: media_object.collection.managers.first) }

      it 'enqueues transcription for eligible sections' do
        post :create_for_media_object, params: { media_object_id: media_object.id }, session: valid_session
        expect(TranscriptionRequest.where(master_file_id: eligible_master_file.id)).to exist
      end
    end

    context 'when a manager of a different collection' do
      let(:user) { User.find_by(username: FactoryBot.create(:media_object).collection.managers.first) }

      it 'redirects to restricted content page' do
        post :create_for_media_object, params: { media_object_id: media_object.id }, session: valid_session
        expect(response).to render_template('errors/restricted_pid')
        expect(TranscriptionRequest.where(master_file_id: eligible_master_file.id)).not_to exist
      end
    end

    context 'when transcription is disabled' do
      before { allow(Settings.transcription).to receive(:enabled).and_return(false) }

      it 'does not create any TranscriptionRequests' do
        post :create_for_media_object, params: { media_object_id: media_object.id }, session: valid_session

        expect(TranscriptionRequest.where(master_file_id: eligible_master_file.id)).not_to exist
      end
    end
  end
end
