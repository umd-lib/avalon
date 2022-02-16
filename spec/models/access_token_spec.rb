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
  end
end
