require 'rails_helper'

RSpec.describe AccessToken, type: :model do
  describe 'defaults' do
    access_token = AccessToken.new

    it 'booleans to default to false' do
      expect(access_token.revoked).to eq(false)
      expect(access_token.expired).to eq(false)
      expect(access_token.allow_streaming).to eq(false)
      expect(access_token.allow_download).to eq(false)
    end

    it 'other fields to default to nil' do
      expect(access_token.expiration).to eq(nil)
      expect(access_token.description).to eq(nil)
      expect(access_token.user).to eq(nil)
    end

    it 'token is generated' do
      expect(access_token.token.length).to eq(16)
    end

    it 'access token is not valid by default' do
      expect(access_token.valid?).to eq(false)
    end

    it 'is valid when given an existing media object and user' do
      media_object = FactoryBot.create(:media_object)
      user = FactoryBot.create(:user)

      access_token.media_object_id = media_object.id
      access_token.user = user

      expect(access_token.valid?).to be true
    end

    it 'adds a read group to the media_object after creation' do
      media_object = FactoryBot.create(:media_object)
      user = FactoryBot.create(:user)
      access_token.user = user

      access_token = AccessToken.create!(user: user, media_object_id: media_object.id, expiration: 7.days.from_now)
      media_object.reload

      expect(media_object.read_groups).to include(access_token.token)
    end
  end
  describe 'the active? flag' do
    let(:access_token) { FactoryBot.create(:access_token) }
    it 'returns false if the token has expired' do
      access_token.expiration = 1.day.ago
      expect(access_token.active?).to be (false)
    end

    it 'returns false if the token has been revoked' do
      access_token.revoked = true
      expect(access_token.active?).to be (false)
    end

    it 'returns true if not expired and not revoked' do
      expect(access_token.should_expire?).to be(false)
      expect(access_token.revoked).to be(false)
      expect(access_token.active?).to be (true)
    end
  end
end
