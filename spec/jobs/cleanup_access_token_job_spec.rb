require 'rails_helper'

describe CleanupAccessTokenJob do
  before do
    @media_object = FactoryBot.create(:media_object)
    @unexpired_access_token = FactoryBot.create(:access_token, media_object_id: @media_object.id)
    @expiring_access_token = FactoryBot.create(:access_token, expiration: 30.minutes.from_now, media_object_id: @media_object.id)
    @expired_access_token = FactoryBot.create(:access_token, expiration: 1.month.ago, media_object_id: @media_object.id)

    # Reload the media object to pick up changes to read_groups
    @media_object.reload
  end

  describe "perform" do
    it 'sets "expired" flag on expiring tokens' do
      travel_to(1.hour.from_now) do
        CleanupAccessTokenJob.perform_now

        expect(@unexpired_access_token.reload.expired?).to be false
        expect(@expiring_access_token.reload.expired?).to be true
        expect(@expired_access_token.reload.expired?).to be true
      end
    end

    it 'removes the read_group on the media object associated with expiring tokens' do
      expect(@media_object.read_groups).to include(@unexpired_access_token.token)
      expect(@media_object.read_groups).to include(@expiring_access_token.token)
      expect(@media_object.read_groups).to_not include(@expired_access_token.token)

      travel_to(1.hour.from_now) do
        CleanupAccessTokenJob.perform_now
        @media_object.reload

        expect(@media_object.read_groups).to include(@unexpired_access_token.token)
        expect(@media_object.read_groups).to_not include(@expiring_access_token.token)
        expect(@media_object.read_groups).to_not include(@expired_access_token.token)
      end
    end
  end
end
