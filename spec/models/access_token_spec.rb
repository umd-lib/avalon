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

    it 'should not add a read group to the media_object if expiration date is past' do
      media_object = FactoryBot.create(:media_object)
      access_token = FactoryBot.create(:access_token, media_object_id: media_object.id, expiration: 7.days.ago)
      media_object.reload

      expect(media_object.read_groups).to_not include(access_token.token)
    end
  end

  describe '#active?' do
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
      expect(access_token.expired?).to be(false)
      expect(access_token.revoked).to be(false)
      expect(access_token.active?).to be(true)
    end
  end

  describe '#expiration=' do
    let(:access_token) { FactoryBot.create(:access_token) }

    it 'when setting the expiration date, the "expired" field should also be updated' do
      expect(access_token[:expired]).to be false

      access_token.expiration = 1.day.ago

      expect(access_token[:expired]).to be true

      access_token.expiration = 1.day.from_now

      expect(access_token[:expired]).to be false
    end

    it 'when created with an expiration date in the past, "expired" field should also be set' do
      access_token_params = FactoryBot.attributes_for(:access_token)
      access_token_params[:expiration] = 1.day.ago
      access_token = AccessToken.new(access_token_params)

      expect(access_token[:expired]).to be true

      access_token.expiration = 1.day.from_now

      expect(access_token[:expired]).to be false
    end
  end

  describe '#allow_streaming_of?' do
    let(:access_token) { FactoryBot.create(:access_token, :allow_streaming) }
    let(:token) { access_token.token }
    let(:media_object_id) { access_token.media_object_id }

    it 'returns false if the token is revoked' do
      access_token.revoked = true
      access_token.save!

      expect(AccessToken.allow_streaming_of?(token, media_object_id)).to be(false)
      expect(access_token.allow_streaming_of?(media_object_id)).to be(false)
    end

    it 'returns false if the token is expired' do
      access_token.expiration = 1.day.ago
      access_token.save!

      expect(AccessToken.allow_streaming_of?(token, media_object_id)).to be(false)
      expect(access_token.allow_streaming_of?(media_object_id)).to be(false)
    end

    it 'returns false if the token does match the given media object id' do
      media_object_id = 'some_other_id'

      expect(AccessToken.allow_streaming_of?(token, media_object_id)).to be(false)
      expect(access_token.allow_streaming_of?(media_object_id)).to be(false)
    end

    it 'returns false if the given media object id is nil' do
      media_object_id = nil
      expect(AccessToken.allow_streaming_of?(token, media_object_id)).to be(false)
      expect(access_token.allow_streaming_of?(media_object_id)).to be(false)
    end

    it 'the class method returns false if the token is not a known token' do
      token = "nonexistent_token"
      expect(AccessToken.allow_streaming_of?(token, media_object_id)).to be(false)
    end

    it 'the class method returns false if the token is nil' do
      token = nil
      expect(AccessToken.allow_streaming_of?(token, media_object_id)).to be(false)
    end

    it 'returns false if the access token is active, but streaming is not allowed' do
      access_token.allow_streaming = false
      access_token.save!

      expect(AccessToken.allow_streaming_of?(token, media_object_id)).to be(false)
      expect(access_token.allow_streaming_of?(media_object_id)).to be(false)
    end

    it 'returns true if the access token is active' do
      expect(AccessToken.allow_streaming_of?(token, media_object_id)).to be(true)
      expect(access_token.allow_streaming_of?(media_object_id)).to be(true)
    end
  end
end
