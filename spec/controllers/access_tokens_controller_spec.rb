require 'rails_helper'

RSpec.describe AccessTokensController, type: :controller do

  context '#new' do
    it "generates an access token with an empty media object field, if no param is provided" do
      login_as(:administrator)

      get :new
      access_token = controller.instance_variable_get('@access_token')
      expect(access_token.media_object_id).to be_nil
    end

    it "generates the access token with the media object id, if provided as a param" do
      login_as(:administrator)
      media_object = FactoryBot.create(:media_object)

      get :new, params: { media_object_id: media_object.id }
      access_token = controller.instance_variable_get('@access_token')
      expect(access_token.media_object_id).to eq(media_object.id)
    end
  end

  context '#create' do
    it 'returns to the "new" page when there is an error' do
      login_as(:administrator)
      media_object = FactoryBot.create(:media_object)
      user = FactoryBot.create(:administrator)

      # "media_object_id" parameter missing
      params = { access_token: { expiration: 1.day.ago, user: user.username,
                                 allow_streaming: true, allow_downloading: false } }

      post :create, params: params

      expect(response).to render_template(:new)
    end

    it 'when an access token is successfully created, goes to the "show" page for that token' do
      login_as(:administrator)
      media_object = FactoryBot.create(:media_object)
      user = FactoryBot.create(:administrator)

      params = { access_token: { media_object_id: media_object.id, expiration: 7.days.from_now, user: user.username,
                                 allow_streaming: true, allow_downloading: false } }

      post :create, params: params

      access_token = AccessToken.last
      expect(response).to redirect_to(access_token_path(access_token))
    end
  end
end
