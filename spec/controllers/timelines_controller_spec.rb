# Copyright 2011-2019, The Trustees of Indiana University and Northwestern
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

# This spec was generated by rspec-rails when you ran the scaffold generator.
# It demonstrates how one might use RSpec to specify the controller code that
# was generated by Rails when you ran the scaffold generator.
#
# It assumes that the implementation code is generated by the rails scaffold
# generator.  If you are using any extension libraries to generate different
# controller code, this generated spec may or may not pass.
#
# It only uses APIs available in rails and/or rspec-rails.  There are a number
# of tools you can use to make these specs even more expressive, but we're
# sticking to rails and rspec-rails APIs to keep things simple and stable.
#
# Compared to earlier versions of this generator, there is very limited use of
# stubs and message expectations in this spec.  Stubs are only used when there
# is no simpler way to get a handle on the object needed for the example.
# Message expectations are only used when there is no simpler way to specify
# that an instance is receiving a specific message.
#
# Also compared to earlier versions of this generator, there are no longer any
# expectations of assigns and templates rendered. These features have been
# removed from Rails core in Rails 5, but can be added back in via the
# `rails-controller-testing` gem.

RSpec.describe TimelinesController, type: :controller do

  # This should return the minimal set of attributes required to create a valid
  # Timeline. As you add validations to Timeline, be sure to
  # adjust the attributes here as well.
  let(:valid_attributes) {
    { title: Faker::Lorem.word, visibility: Timeline::PUBLIC, user: user, source: source_url }
  }

  let(:master_file) { FactoryBot.create(:master_file) }
  let(:source_url) { master_file_url(master_file, params: { t: '30,60' }) }

  let(:invalid_attributes) {
    { visibility: 'unknown' }
  }

  # This should return the minimal set of values that should be in the session
  # in order to pass any filters (e.g. authentication) defined in
  # TimelinesController. Be sure to keep this updated too.
  let(:valid_session) { {} }

  let(:user) { login_as :user }

  describe 'security' do
    let(:timeline) { FactoryBot.create(:timeline) }

    context 'with unauthenticated user' do
      # New is isolated here due to issues caused by the controller instance not being regenerated
      it "should redirect to sign in" do
        expect(get :new).to redirect_to(/#{Regexp.quote(new_user_session_path)}\?url=.*/)
      end
      it "all routes should redirect to sign in" do
        expect(get :index).to redirect_to(/#{Regexp.quote(new_user_session_path)}\?url=.*/)
        expect(get :edit, params: { id: timeline.id }).to redirect_to(/#{Regexp.quote(new_user_session_path)}\?url=.*/)
        expect(post :create).to redirect_to(/#{Regexp.quote(new_user_session_path)}\?url=.*/)
        expect(put :update, params: { id: timeline.id }).to redirect_to(/#{Regexp.quote(new_user_session_path)}\?url=.*/)
        expect(delete :destroy, params: { id: timeline.id }).to redirect_to(/#{Regexp.quote(new_user_session_path)}\?url=.*/)
      end
      context 'with a public timeline' do
        let(:timeline) { FactoryBot.create(:timeline, visibility: Timeline::PUBLIC) }
        it "should return the timeline view page" do
          expect(get :show, params: { id: timeline.id }).to be_successful
          expect(get :manifest, params: { id: timeline.id, format: :json }).to be_successful
        end
      end
      context 'with a private timeline' do
        it "should NOT return the timeline view page" do
          expect(get :show, params: { id: timeline.id }).to redirect_to(/#{Regexp.quote(new_user_session_path)}\?url=.*/)
          expect(get :manifest, params: { id: timeline.id, format: :json }).to be_unauthorized
        end
      end
      context 'with a private timeline and token' do
        let(:timeline) { FactoryBot.create(:timeline, :with_access_token) }
        it "should return the timeline view page" do
          expect(get :show, params: { id: timeline.id, token: timeline.access_token }).to be_successful
          expect(get :manifest, params: { id: timeline.id, token: timeline.access_token, format: :json }).to be_successful
        end
      end
    end
    context 'with end-user' do
      before do
        login_as :user
      end
      it "all routes should redirect to /" do
        expect(get :edit, params: { id: timeline.id }).to redirect_to(root_path)
        expect(put :update, params: { id: timeline.id }).to redirect_to(root_path)
        expect(delete :destroy, params: { id: timeline.id }).to redirect_to(root_path)
      end
      context 'with a public timeline' do
        let(:timeline) { FactoryBot.create(:timeline, visibility: Timeline::PUBLIC) }
        it "should return the timeline view page" do
          expect(get :show, params: { id: timeline.id }).to be_successful
          expect(get :manifest, params: { id: timeline.id, format: :json }).to be_successful
        end
      end
      context 'with a private timeline' do
        it "should NOT return the timeline view page" do
          expect(get :show, params: { id: timeline.id }).to redirect_to(root_path)
          expect(get :manifest, params: { id: timeline.id, format: :json }).to be_unauthorized
        end
      end
      context 'with a private timeline and token' do
        let(:timeline) { FactoryBot.create(:timeline, :with_access_token) }
        it "should return the timeline view page" do
          expect(get :show, params: { id: timeline.id, token: timeline.access_token }).to be_successful
          expect(get :manifest, params: { id: timeline.id, token: timeline.access_token, format: :json }).to be_successful
        end
      end
    end
  end

  describe "GET #index" do
    it 'assigns accessible timelines as @timelines' do
      # TODO: test non-accessible timelines not appearing
      timeline = Timeline.create! valid_attributes
      get :index, params: {}, session: valid_session
      expect(assigns(:timelines)).to eq([timeline])
    end
  end

  describe "GET #show" do
    it "renders the timeliner tool" do
      timeline = Timeline.create! valid_attributes
      get :show, params: {id: timeline.to_param}, session: valid_session
      expect(response).to be_successful
    end

    context "with format json" do
      let(:manifest) do
        {
          "@context": [
            "http://www.w3.org/ns/anno.jsonld",
            "http://iiif.io/api/presentation/3/context.json"
          ],
          "id": "https://example.com/timelines/1.json",
          "type": "Manifest",
          "label": { "en": [ "Timeline 1" ] }
        }
      end
      it "returns the timeline" do
        timeline = Timeline.create! valid_attributes.merge(manifest: manifest.to_json)
        get :show, params: {id: timeline.to_param, format: :json}, session: valid_session
        expect(response).to be_successful
        response_json = JSON.parse(response.body)
        expect(response_json["id"]).to eq timeline.id
        expect(response_json["visibility"]).to eq timeline.visibility
        expect(response_json["manifest"]).to eq timeline.manifest
      end
    end
  end

  describe "GET #new" do
    before do
      login_as :user
    end

    it "returns a success response" do
      get :new, params: {}, session: valid_session
      expect(response).to be_successful
      expect(assigns(:timeline)).to be_a_new(Timeline)
    end
  end

  describe "GET #edit" do
    it "returns a success response" do
      timeline = Timeline.create! valid_attributes
      get :edit, params: {id: timeline.to_param}, session: valid_session
      expect(response).to be_successful
      expect(assigns(:timeline)).to eq(timeline)
    end

    it 'assigns the requested timeline as @timeline' do
      timeline = Timeline.create! valid_attributes
      get :edit, params: { id: timeline.to_param }, session: valid_session
      expect(assigns(:timeline)).to eq(timeline)
    end
  end

  describe "POST #create" do
    context "with valid params" do
      it "creates a new Timeline" do
        expect {
          post :create, params: {timeline: valid_attributes}, session: valid_session
        }.to change(Timeline, :count).by(1)
      end

      it 'assigns a newly created timeline as @timeline' do
        post :create, params: { timeline: valid_attributes }, session: valid_session
        expect(assigns(:timeline)).to be_a(Timeline)
        expect(assigns(:timeline)).to be_persisted
      end

      it "redirects to the created timeline" do
        post :create, params: {timeline: valid_attributes}, session: valid_session
        expect(response).to redirect_to(Timeline.last)
      end

      it 'generates a token if visibility is private-with-token' do
        post :create, params: { timeline: valid_attributes.merge(visibility: Timeline::PRIVATE_WITH_TOKEN) }, session: valid_session
        expect(assigns(:timeline).access_token).not_to be_blank
      end
    end

    context "with structure" do
      let(:master_file) { FactoryBot.create(:master_file, :with_structure) }
      it "creates a new Timeline with initialize manifest structure" do
        post :create, params: { timeline: valid_attributes, include_structure: true }, session: valid_session
        timeline = Timeline.last
        structures = JSON.parse(timeline.manifest)['structures']
        expect(structures.count).to eq(6)
        expect(structures.first['label']['en'].first).to eq('Copland, Three Piano Excerpts from Our Town')
        expect(structures.last['label']['en'].first).to eq('')
      end
    end

    context "with invalid params" do
      before do
        login_as :user
      end

      it "returns a success response (i.e. to display the 'new' template)" do
        post :create, params: {timeline: invalid_attributes}, session: valid_session
        expect(response).to be_successful
        expect(assigns(:timeline)).to be_a_new(Timeline)
      end

      it "re-renders the 'new' template" do
        post :create, params: { timeline: invalid_attributes }, session: valid_session
        expect(response).to render_template('new')
      end
    end

    context 'with json request' do
      context "with valid params" do
        it "creates a new Timeline" do
          expect {
            post :create, params: { timeline: valid_attributes, format: :json }, session: valid_session
          }.to change(Timeline, :count).by(1)
        end

        it "returns the created timeline as json" do
          post :create, params: { timeline: valid_attributes, format: :json }, session: valid_session
          expect(response).to be_created
          expect(response.content_type).to eq 'application/json'
          expect(response.location).to eq "http://test.host/timelines/1"
          response_json = JSON.parse(response.body)
          new_timeline = Timeline.last
          expect(response_json["manifest"]).to eq new_timeline.manifest
          expect(response_json["title"]).to eq new_timeline.title
        end

        it 'generates a token if visibility is private-with-token' do
          post :create, params: { timeline: valid_attributes.merge(visibility: Timeline::PRIVATE_WITH_TOKEN), format: :json }, session: valid_session
          expect(response).to be_successful
          expect(response.content_type).to eq 'application/json'
          response_json = JSON.parse(response.body)
          expect(response_json["access_token"]).not_to be_blank
        end
      end

      context "with invalid params" do
        before do
          login_as :user
        end

        it "returns an unprocessable_entity response with the errors" do
          post :create, params: { timeline: invalid_attributes, format: :json }, session: valid_session
          expect(response).to be_unprocessable
          expect(response.content_type).to eq 'application/json'
          expect(JSON.parse(response.body)).not_to be_blank
        end
      end

      context 'with manifest body' do
        let(:source) { "http://example.com/media_objects/abc123/section/dce456?t=0," }
        let(:title) { "Cloned manifest" }
        let(:description) { 'The manifest description' }
        let(:submitted_manifest) do
          {
            "@context": [
              "http://www.w3.org/ns/anno.jsonld",
              "http://iiif.io/api/presentation/3/context.json"
            ],
            "id": "https://example.com/timelines/1.json",
            "type": "Manifest",
            "label": {
              "en": [title]
            },
            "summary": {
              "en": [description]
            },
            "homepage": {
              "id": source,
              "type": "Text",
              "label": {
                "en": ["View Source Item"]
              },
              "format": "text/html"
            }
          }
        end

        before do
          user
        end

        it "creates a new Timeline" do
          expect {
            post :create, params: { format: :json }, body: submitted_manifest.to_json, session: valid_session
          }.to change(Timeline, :count).by(1)
        end

        it 'creates a new timeline' do
          post :create, params: { format: :json }, body: submitted_manifest.to_json, session: valid_session
          new_timeline = Timeline.last
          expect(response).to be_created
          expect(response.content_type).to eq 'application/json'
          expect(response.location).to eq "http://test.host/timelines/#{new_timeline.id}"
          response_json = JSON.parse(response.body)
          # Ensure that stored timeline, response timeline, and submitted manifest all match
          expect(response_json["manifest"]).to eq new_timeline.manifest
          expect(new_timeline.manifest).to eq submitted_manifest.to_json
          expect(response_json["title"]).to eq new_timeline.title
          expect(new_timeline.title).to eq title
          expect(response_json["user_id"]).to eq new_timeline.user_id
          expect(new_timeline.user_id).to eq user.id
          expect(response_json["source"]).to eq new_timeline.source
          expect(new_timeline.source).to eq source
        end
      end
    end
  end

  describe "PUT #update" do
    context "with valid params" do
      let(:new_attributes) {
        { title: Faker::Lorem.word, visibility: Timeline::PUBLIC, description: Faker::Lorem.sentence }
      }

      it "updates the requested timeline" do
        timeline = Timeline.create! valid_attributes
        put :update, params: {id: timeline.to_param, timeline: new_attributes}, session: valid_session
        timeline.reload
        expect(timeline.title).to eq new_attributes[:title]
        expect(timeline.visibility).to eq new_attributes[:visibility]
        expect(timeline.description).to eq new_attributes[:description]
      end

      it 'assigns the requested timeline as @timeline' do
        timeline = Timeline.create! valid_attributes
        put :update, params: { id: timeline.to_param, timeline: new_attributes }, session: valid_session
        expect(assigns(:timeline)).to eq(timeline)
      end

      it "redirects to the timeline" do
        timeline = Timeline.create! valid_attributes
        put :update, params: {id: timeline.to_param, timeline: valid_attributes}, session: valid_session
        expect(response).to redirect_to(edit_timeline_path(timeline))
      end

      it 'generates a token if visibility is private-with-token' do
        timeline = Timeline.create! valid_attributes
        put :update, params: { id: timeline.to_param, timeline: { visibility: Timeline::PRIVATE_WITH_TOKEN } }, session: valid_session
        timeline.reload
        expect(timeline.access_token).not_to be_blank
      end
    end

    context "with invalid params" do
      it 'assigns the timeline as @timeline' do
        timeline = Timeline.create! valid_attributes
        put :update, params: { id: timeline.to_param, timeline: invalid_attributes }, session: valid_session
        expect(assigns(:timeline)).to eq(timeline)
      end

      it "returns a success response (i.e. to display the 'edit' template)" do
        timeline = Timeline.create! valid_attributes
        put :update, params: {id: timeline.to_param, timeline: invalid_attributes}, session: valid_session
        expect(response).to be_successful
        expect(response).to render_template('edit')
      end
    end
  end

  describe "DELETE #destroy" do
    it "destroys the requested timeline" do
      timeline = Timeline.create! valid_attributes
      expect {
        delete :destroy, params: {id: timeline.to_param}, session: valid_session
      }.to change(Timeline, :count).by(-1)
    end

    it "redirects to the timelines list" do
      timeline = Timeline.create! valid_attributes
      delete :destroy, params: {id: timeline.to_param}, session: valid_session
      expect(response).to redirect_to(timelines_url)
    end
  end

  describe 'POST #duplicate' do
    before do
      login_as :user
    end
    let(:new_attributes) do
      { title: Faker::Lorem.word, visibility: Timeline::PUBLIC, description: Faker::Lorem.sentence, user: user }
    end
    let(:timeline) { FactoryBot.create(:timeline, new_attributes) }

    it 'duplicates a timeline' do
      post :duplicate, params: { format: 'json', old_timeline_id: timeline.id, timeline: { 'title' => timeline.title, 'description' => timeline.description, 'visibility' => timeline.visibility } }
      expect(response.body).not_to be_empty
      parsed_response = JSON.parse(response.body)

      new_timeline = Timeline.find(parsed_response['timeline']['id'])

      expect(new_timeline.id).not_to eq timeline.id
      expect(new_timeline.user_id).to eq timeline.user_id
      expect(new_timeline.visibility).to eq timeline.visibility
      expect(new_timeline.title).to eq timeline.title
      expect(new_timeline.description).to eq timeline.description
      expect(new_timeline.manifest).to eq timeline.manifest
      expect(new_timeline.source).to eq timeline.source
      expect(new_timeline.tags).to eq timeline.tags
    end
  end

  describe '#regenerate_access_token' do
    before do
      login_as :user
    end

    let(:timeline) { FactoryBot.create(:timeline, user: user, visibility: Timeline::PRIVATE_WITH_TOKEN) }

    it 'regenerates the access token' do
      old_token = timeline.access_token
      put :regenerate_access_token, params: { id: timeline.to_param }, session: valid_session
      timeline.reload
      expect(timeline.access_token).not_to be_blank
      expect(timeline.access_token).not_to eq old_token
    end

    it 'returns the access token' do
      put :regenerate_access_token, params: { id: timeline.to_param }, session: valid_session
      expect(response).to be_successful
      timeline.reload
      expect(response.body).to include "\"access_token_url\":\"#{controller.access_token_url(timeline)}\""
    end
  end

  describe '#access_token_url' do
    let(:timeline) { FactoryBot.build(:timeline, id: 1, access_token: 'foo') }

    it 'returns a url for the timeline with the access token' do
      expect(controller.access_token_url(timeline)).to eq "#{root_url}timelines/1?token=foo"
    end
  end

  describe '#manifest' do
    let(:manifest) do
      {
        "@context": [
          "http://www.w3.org/ns/anno.jsonld",
          "http://iiif.io/api/presentation/3/context.json"
        ],
        "id": "https://example.com/timelines/1.json",
        "type": "Manifest",
        "label": { "en": [ "Timeline 1" ] }
      }
    end
    it "returns the timeline manifest" do
      timeline = Timeline.create! valid_attributes.merge(manifest: manifest.to_json)
      get :manifest, params: {id: timeline.to_param, format: :json}, session: valid_session
      expect(response).to be_successful
      expect(response.body).to eq timeline.manifest
    end

    context 'when timeline is public' do
      it 'returns the manifest without logging in' do
        timeline = Timeline.create! valid_attributes.merge(manifest: manifest.to_json)
        sign_out user
        get :manifest, params: {id: timeline.to_param, format: :json}, session: valid_session
        expect(response).to be_successful
        expect(response.body).to eq timeline.manifest
      end
    end
  end

  describe '#manifest_update' do
    let(:manifest) do
      {
        "@context": [
          "http://www.w3.org/ns/anno.jsonld",
          "http://iiif.io/api/presentation/3/context.json"
        ],
        "id": "https://example.com/timelines/1.json",
        "type": "Manifest",
        "label": { "en": [ "Timeline 1" ] }
      }
    end
    it "returns the timeline manifest" do
      timeline = Timeline.create! valid_attributes.merge(manifest: {}.to_json)
      post :manifest_update, body: manifest.to_json, params: { id: timeline.id, format: :json }, session: valid_session
      timeline.reload
      expect(response).to be_successful
      expect(response.body).to eq timeline.manifest
      expect(timeline.manifest).to eq manifest.to_json
    end
  end

  describe '#timeliner' do
    it 'returns the timeliner iframe' do
      expect(get :timeliner).to be_successful
    end
  end
end
