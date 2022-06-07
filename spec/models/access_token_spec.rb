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

  context 'is valid when given an existing media object, an expiration in the future, and' do
    it 'an admin user' do
      admin_user = FactoryBot.create(:admin)
      access_token = FactoryBot.create(:access_token, user: admin_user)

      expect(access_token.valid?).to be true
    end

    it 'a manager of the collection' do
      manager = FactoryBot.create(:manager)
      collection = FactoryBot.create(:collection, :with_manager, manager: manager)
      media_object = FactoryBot.create(:media_object, collection: collection)
      access_token = FactoryBot.create(:access_token, media_object_id: media_object.id, user: manager)

      expect(access_token.valid?).to be true
    end

    it 'an editor of the collection' do
      editor = FactoryBot.create(:user) # Any user can be an editor
      collection = FactoryBot.create(:collection, :with_editor, editor: editor)
      media_object = FactoryBot.create(:media_object, collection: collection)
      access_token = FactoryBot.create(:access_token, media_object_id: media_object.id, user: editor)

      expect(access_token.valid?).to be true
    end

    it 'a depositor of the collection' do
      depositor = FactoryBot.create(:user) # Any user can be a depositor
      collection = FactoryBot.create(:collection, :with_depositor, depositor: depositor)
      media_object = FactoryBot.create(:media_object, collection: collection)
      access_token = FactoryBot.create(:access_token, media_object_id: media_object.id, user: depositor)

      expect(access_token.valid?).to be true
    end
  end

  it 'cannot be created if user is not an admin, or an manager, editor, or depositor of the collection' do
    user = FactoryBot.create(:user)
    media_object = FactoryBot.create(:media_object)
    collection = media_object.collection
    expect(collection.managers.include?(user)).to be false
    expect(collection.editors.include?(user)).to be false
    expect(collection.depositors.include?(user)).to be false

    expect { FactoryBot.create(:access_token, user: user) }.to raise_exception(ActiveRecord::RecordInvalid)
  end

  it 'cannot be created with an expiration date in the past' do
    expect { FactoryBot.create(:access_token, expiration: 1.day.ago) }.to raise_exception(ActiveRecord::RecordInvalid)
  end

  context 'read group' do
    let (:access_token) { FactoryBot.create(:access_token) }
    let (:media_object) { MediaObject.find(access_token.media_object_id) }
    let (:user) { access_token.user }

    it 'should be added to the media_object after creation' do
      expect(media_object.reload.read_groups).to include(access_token.token)
    end

    # it 'should not be added to the media_object if expiration date is in the past' do
    #   access_token = FactoryBot.create(:access_token, expiration: 7.days.ago)
    #   media_object = MediaObject.find(access_token.media_object_id)

    #   expect(media_object.read_groups).to_not include(access_token.token)
    # end

    it 'should not be added to the media_object if the read group already is present' do
      expect(media_object.read_groups).to include(access_token.token)
      expect(media_object.read_groups.length).to be(1)

      # Attempt to add read group again
      access_token.add_read_group
      media_object.reload

      expect(media_object.read_groups).to include(access_token.token)
      expect(media_object.read_groups.length).to be(1)
    end
  end

  describe '#active?' do
    it 'returns false if the token has expired' do
      access_token = FactoryBot.create(:access_token, expiration: 30.minutes.from_now)
      travel_to(1.hour.from_now) do
         expect(access_token.active?).to be (false)
      end
    end

    let(:access_token) { FactoryBot.create(:access_token) }

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
    it 'cannot be set after object is created' do
      access_token = FactoryBot.create(:access_token, expiration: 1.day.from_now)

      current_expiration = access_token.expiration
      new_expiration = 2.days.from_now

      expect(Rails.logger).to receive(:warn).with(/Attempted to set expiration on existing record/)

      access_token.expiration = new_expiration
      access_token.save!

      expect(access_token[:expiration]).to eq(current_expiration)
    end

    it 'when created with an expiration date in the past, "expired" field should also be set' do
      access_token_params = FactoryBot.attributes_for(:access_token)
      access_token_params[:expiration] = 1.day.ago
      access_token = AccessToken.new(access_token_params)

      expect(access_token[:expired]).to be true
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
      access_token = FactoryBot.create(:access_token, :allow_streaming, expiration: 30.minutes.from_now)

      travel_to(1.hour.from_now) do
        token = access_token.token
        media_object_id = access_token.media_object_id

        expect(AccessToken.allow_streaming_of?(token, media_object_id)).to be(false)
        expect(access_token.allow_streaming_of?(media_object_id)).to be(false)
      end
    end

    it 'returns false if the token does not match the given media object id' do
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

  describe '#remove_read_group' do
    let(:access_token) { FactoryBot.create(:access_token) }
    let(:token) { access_token.token }
    let(:media_object) { MediaObject.find(access_token.media_object_id) }

    it 'removes the read_group associated with the token from the media object' do
      expect(media_object.read_groups).to include(token)

      access_token.remove_read_group
      expect(media_object.reload.read_groups).not_to include(token)
    end
  end

  describe '#expire' do
    let (:access_token) { FactoryBot.create(:access_token, expiration: 30.minutes.from_now) }
    let (:media_object) { MediaObject.find(access_token.media_object_id) }

    it 'does nothing if the expiration date is not in the past' do
      access_token.expire
      expect(access_token.reload.expired).to be false
      expect(access_token.reload.expired?).to be false
    end

    it 'sets the "expired" field to true' do
      expect(access_token.expired?).to be false

      travel_to(1.hour.from_now) do
        access_token.expire
        expect(access_token.reload.expired).to be true
        expect(access_token.reload.expired?).to be true
      end
    end

    it 'removes the token from the read_group of the associated media object' do
      expect(access_token.expired?).to be false
      expect(media_object.read_groups).to include(access_token.token)

      travel_to(1.hour.from_now) do
        access_token.expire

        expect(access_token.expired?).to be true
        expect(media_object.reload.read_groups).to_not include(access_token.token)
      end
    end
  end
end
