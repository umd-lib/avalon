require 'rails_helper'

RSpec.describe AccessTokensController, type: :controller do

  context '#new' do
    context 'when a "media_object_id" param is not provided' do
      it 'generates an access token with an empty media object field' do
        login_as(:administrator)

        get :new
        access_token = controller.instance_variable_get('@access_token')
        expect(access_token.media_object_id).to be_nil
      end

      it 'sets the "Cancel" button to return to the access tokens list page' do
        login_as(:administrator)

        get :new
        cancel_link = controller.instance_variable_get('@cancel_link')
        expect(cancel_link).to eq (access_tokens_path)
      end
    end

    context 'when media_object_id param is provided' do
      it 'generates the access token with the media object id' do
        login_as(:administrator)
        media_object = FactoryBot.create(:media_object)

        get :new, params: { media_object_id: media_object.id }
        access_token = controller.instance_variable_get('@access_token')
        expect(access_token.media_object_id).to eq(media_object.id)
      end

      it 'sets the "Cancel" button to return to the media object Access Control page' do
        login_as(:administrator)
        media_object = FactoryBot.create(:media_object)

        get :new, params: { media_object_id: media_object.id }
        cancel_link = controller.instance_variable_get('@cancel_link')
        expect(cancel_link).to eq (edit_media_object_path(id: media_object.id, step: 'access-control'))
      end
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

      # Cancel button returns to access tokens list page
      cancel_link = controller.instance_variable_get('@cancel_link')
      expect(cancel_link).to eq (access_tokens_path)
    end

    it 'returns to the "new" page when no expiration date is provided' do
      login_as(:administrator)
      media_object = FactoryBot.create(:media_object)
      user = FactoryBot.create(:administrator)

      params = { access_token: { media_object_id: media_object.id, user: user.username,
                                 expiration: '',
                                 allow_streaming: true, allow_downloading: false } }

      post :create, params: params

      expect(response).to render_template(:new)

      # Cancel button returns to media object Access Control page (because there
      # is a media_object_id)
      cancel_link = controller.instance_variable_get('@cancel_link')
      expect(cancel_link).to eq (edit_media_object_path(id: media_object.id, step: 'access-control'))
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

  context '#show' do
    it 'provides a link to the Media Object Access Control page' do
      user = login_as(:administrator)
      access_token = FactoryBot.create(:access_token, user: user)

      get :show, params: { id: access_token.id }

      media_object_access_control_link = controller.instance_variable_get('@media_object_access_control_link')
      expect(media_object_access_control_link).to eq(edit_media_object_path(id: access_token.media_object_id, step: 'access-control'))
    end

    context 'for active tokens' do
      it 'includes a text snippet containing information to provide to the patron' do
        user = login_as(:administrator)
        access_token = FactoryBot.create(:access_token, user: user)

        get :show, params: { id: access_token.id }
        expect(controller.instance_variable_get('@info_for_patron_snippet')).to_not be_empty
      end
    end
    context 'for expired or revoked tokens' do
      it 'does not include a text snippet containing information to provide to the patron' do
        user = login_as(:administrator)
        access_token = FactoryBot.create(:access_token, expiration: 30.minutes.from_now, user: user)

        # Expired token
        travel_to(1.hour.from_now) do
          get :show, params: { id: access_token.id }
          expect(controller.instance_variable_get('@info_for_patron_snippet')).to be_nil
        end

        # Revoked token
        access_token.revoked=true
        access_token.save!
        get :show, params: { id: access_token.id }
        expect(controller.instance_variable_get('@info_for_patron_snippet')).to be_nil
      end
    end
  end

  context '#edit' do
    it 'provides a Cancel link back to the "show" access page' do
      user = login_as(:administrator)
      access_token = FactoryBot.create(:access_token, user: user)

      get :edit, params: { id: access_token.id }
      cancel_link = controller.instance_variable_get('@cancel_link')
      expect(cancel_link).to eq(access_token_path(access_token))
    end
  end
end
