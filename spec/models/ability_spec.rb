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
# UMD Customization
require "cancan/matchers"
# End UMD Customization

describe Ability, type: :model do
  describe 'non-logged in users' do
    it 'only belongs to the public group' do
      expect(Ability.new(nil).user_groups).to eq ["public"]
    end
  end

  describe 'repository read-only mode' do
    # Next line is let! to ensure that it runs before the before block which would stop the object from being created
    let!(:media_object) { FactoryBot.create(:media_object) }
    let(:media_object_proxy) { SpeedyAF::Base.find(media_object.id) }
    let(:collection) { media_object.collection }
    let(:collection_proxy) { SpeedyAF::Base.find(collection.id) }
    let(:unit) { collection.unit }
    let(:unit_proxy) { SpeedyAF::Base.find(unit.id) }
    let(:admin) { FactoryBot.create(:administrator) }
    let(:session) { {} }
    subject(:admin_ability) { Ability.new(admin, session) }

    before { allow(Settings).to receive(:repository_read_only_mode).and_return(read_only) }

    context 'with read-only enabled' do
      let(:read_only) { true }

      it 'has read-only abilities' do
        expect(subject.can?(:manage, :all)).to eq true
        expect(subject.can?(:manage, MediaObject)).to eq true
        expect(subject.can?(:discover_everything, MediaObject)).to eq true

        expect(subject.can?(:read, media_object)).to eq true
        expect(subject.can?(:read, media_object_proxy)).to eq true
        expect(subject.can?(:read, collection)).to eq true
        expect(subject.can?(:read, collection_proxy)).to eq true
        expect(subject.can?(:read, unit)).to eq true
        expect(subject.can?(:read, unit_proxy)).to eq true

        expect(subject.can?(:create, MediaObject)).to eq false
        expect(subject.can?(:read, MediaObject)).to eq true
        expect(subject.can?(:edit, MediaObject)).to eq false
        expect(subject.can?(:update, MediaObject)).to eq false
        expect(subject.can?(:destroy, MediaObject)).to eq false
        expect(subject.can?(:update_access_control, MediaObject)).to eq false
        expect(subject.can?(:unpublish, MediaObject)).to eq false
        expect(subject.can?(:intercom_push, MediaObject)).to eq false

        expect(subject.can?(:create, SpeedyAF::Proxy::MediaObject)).to eq false
        expect(subject.can?(:read, SpeedyAF::Proxy::MediaObject)).to eq true
        expect(subject.can?(:edit, SpeedyAF::Proxy::MediaObject)).to eq false
        expect(subject.can?(:update, SpeedyAF::Proxy::MediaObject)).to eq false
        expect(subject.can?(:destroy, SpeedyAF::Proxy::MediaObject)).to eq false
        expect(subject.can?(:update_access_control, SpeedyAF::Proxy::MediaObject)).to eq false
        expect(subject.can?(:unpublish, SpeedyAF::Proxy::MediaObject)).to eq false

        expect(subject.can?(:create, MasterFile)).to eq false
        expect(subject.can?(:read, MasterFile)).to eq true
        expect(subject.can?(:edit, MasterFile)).to eq false
        expect(subject.can?(:update, MasterFile)).to eq false
        expect(subject.can?(:destroy, MasterFile)).to eq false

        expect(subject.can?(:create, SpeedyAF::Proxy::MasterFile)).to eq false
        expect(subject.can?(:read, SpeedyAF::Proxy::MasterFile)).to eq true
        expect(subject.can?(:edit, SpeedyAF::Proxy::MasterFile)).to eq false
        expect(subject.can?(:update, SpeedyAF::Proxy::MasterFile)).to eq false
        expect(subject.can?(:destroy, SpeedyAF::Proxy::MasterFile)).to eq false

        expect(subject.can?(:create, Derivative)).to eq false
        expect(subject.can?(:read, Derivative)).to eq true
        expect(subject.can?(:edit, Derivative)).to eq false
        expect(subject.can?(:update, Derivative)).to eq false
        expect(subject.can?(:destroy, Derivative)).to eq false

        expect(subject.can?(:create, SpeedyAF::Proxy::Derivative)).to eq false
        expect(subject.can?(:read, SpeedyAF::Proxy::Derivative)).to eq true
        expect(subject.can?(:edit, SpeedyAF::Proxy::Derivative)).to eq false
        expect(subject.can?(:update, SpeedyAF::Proxy::Derivative)).to eq false
        expect(subject.can?(:destroy, SpeedyAF::Proxy::Derivative)).to eq false

        expect(subject.can?(:create, Admin::Collection)).to eq false
        expect(subject.can?(:read, Admin::Collection)).to eq true
        expect(subject.can?(:edit, Admin::Collection)).to eq false
        expect(subject.can?(:update, Admin::Collection)).to eq false
        expect(subject.can?(:destroy, Admin::Collection)).to eq false
        expect(subject.can?(:update_unit, Admin::Collection)).to eq false
        expect(subject.can?(:update_access_control, Admin::Collection)).to eq false
        expect(subject.can?(:update_managers, Admin::Collection)).to eq false
        expect(subject.can?(:update_editors, Admin::Collection)).to eq false
        expect(subject.can?(:update_depositors, Admin::Collection)).to eq false

        expect(subject.can?(:create, SpeedyAF::Proxy::Admin::Collection)).to eq false
        expect(subject.can?(:read, SpeedyAF::Proxy::Admin::Collection)).to eq true
        expect(subject.can?(:edit, SpeedyAF::Proxy::Admin::Collection)).to eq false
        expect(subject.can?(:update, SpeedyAF::Proxy::Admin::Collection)).to eq false
        expect(subject.can?(:destroy, SpeedyAF::Proxy::Admin::Collection)).to eq false
        expect(subject.can?(:update_unit, SpeedyAF::Proxy::Admin::Collection)).to eq false
        expect(subject.can?(:update_access_control, SpeedyAF::Proxy::Admin::Collection)).to eq false
        expect(subject.can?(:update_managers, SpeedyAF::Proxy::Admin::Collection)).to eq false
        expect(subject.can?(:update_editors, SpeedyAF::Proxy::Admin::Collection)).to eq false
        expect(subject.can?(:update_depositors, SpeedyAF::Proxy::Admin::Collection)).to eq false

        expect(subject.can?(:destroy, Admin::CollectionPresenter)).to eq false

        expect(subject.can?(:create, Admin::Unit)).to eq false
        expect(subject.can?(:read, Admin::Unit)).to eq true
        expect(subject.can?(:edit, Admin::Unit)).to eq false
        expect(subject.can?(:update, Admin::Unit)).to eq false
        expect(subject.can?(:destroy, Admin::Unit)).to eq false
        expect(subject.can?(:update_unit_admins, Admin::Unit)).to eq false
        expect(subject.can?(:update_access_control, Admin::Unit)).to eq false
        expect(subject.can?(:update_managers, Admin::Unit)).to eq false
        expect(subject.can?(:update_editors, Admin::Unit)).to eq false
        expect(subject.can?(:update_depositors, Admin::Unit)).to eq false

        expect(subject.can?(:create, SpeedyAF::Proxy::Admin::Unit)).to eq false
        expect(subject.can?(:read, SpeedyAF::Proxy::Admin::Unit)).to eq true
        expect(subject.can?(:edit, SpeedyAF::Proxy::Admin::Unit)).to eq false
        expect(subject.can?(:update, SpeedyAF::Proxy::Admin::Unit)).to eq false
        expect(subject.can?(:destroy, SpeedyAF::Proxy::Admin::Unit)).to eq false
        expect(subject.can?(:update_unit_admins, SpeedyAF::Proxy::Admin::Unit)).to eq false
        expect(subject.can?(:update_access_control, SpeedyAF::Proxy::Admin::Unit)).to eq false
        expect(subject.can?(:update_managers, SpeedyAF::Proxy::Admin::Unit)).to eq false
        expect(subject.can?(:update_editors, SpeedyAF::Proxy::Admin::Unit)).to eq false
        expect(subject.can?(:update_depositors, SpeedyAF::Proxy::Admin::Unit)).to eq false

        expect(subject.can?(:destroy, Admin::UnitPresenter)).to eq false
      end
    end

    context 'with read-only disabled' do
      let(:read_only) { false }

      it 'has all abilities' do
        expect(subject.can?(:manage, :all)).to eq true
        expect(subject.can?(:manage, MediaObject)).to eq true
        expect(subject.can?(:discover_everything, MediaObject)).to eq true

        expect(subject.can?(:read, media_object)).to eq true
        expect(subject.can?(:read, collection)).to eq true
        expect(subject.can?(:read, unit)).to eq true

        expect(subject.can?(:create, MediaObject)).to eq true
        expect(subject.can?(:read, MediaObject)).to eq true
        expect(subject.can?(:edit, MediaObject)).to eq true
        expect(subject.can?(:update, MediaObject)).to eq true
        expect(subject.can?(:destroy, MediaObject)).to eq true
        expect(subject.can?(:update_access_control, MediaObject)).to eq true
        expect(subject.can?(:unpublish, MediaObject)).to eq true

        expect(subject.can?(:create, SpeedyAF::Proxy::MediaObject)).to eq true
        expect(subject.can?(:read, SpeedyAF::Proxy::MediaObject)).to eq true
        expect(subject.can?(:edit, SpeedyAF::Proxy::MediaObject)).to eq true
        expect(subject.can?(:update, SpeedyAF::Proxy::MediaObject)).to eq true
        expect(subject.can?(:destroy, SpeedyAF::Proxy::MediaObject)).to eq true
        expect(subject.can?(:update_access_control, SpeedyAF::Proxy::MediaObject)).to eq true
        expect(subject.can?(:unpublish, SpeedyAF::Proxy::MediaObject)).to eq true
        expect(subject.can?(:intercom_push, MediaObject)).to eq true
 
        expect(subject.can?(:create, MasterFile)).to eq true
        expect(subject.can?(:read, MasterFile)).to eq true
        expect(subject.can?(:edit, MasterFile)).to eq true
        expect(subject.can?(:update, MasterFile)).to eq true
        expect(subject.can?(:destroy, MasterFile)).to eq true

        expect(subject.can?(:create, SpeedyAF::Proxy::MasterFile)).to eq true
        expect(subject.can?(:read, SpeedyAF::Proxy::MasterFile)).to eq true
        expect(subject.can?(:edit, SpeedyAF::Proxy::MasterFile)).to eq true
        expect(subject.can?(:update, SpeedyAF::Proxy::MasterFile)).to eq true
        expect(subject.can?(:destroy, SpeedyAF::Proxy::MasterFile)).to eq true

        expect(subject.can?(:create, Derivative)).to eq true
        expect(subject.can?(:read, Derivative)).to eq true
        expect(subject.can?(:edit, Derivative)).to eq true
        expect(subject.can?(:update, Derivative)).to eq true
        expect(subject.can?(:destroy, Derivative)).to eq true

        expect(subject.can?(:create, SpeedyAF::Proxy::Derivative)).to eq true
        expect(subject.can?(:read, SpeedyAF::Proxy::Derivative)).to eq true
        expect(subject.can?(:edit, SpeedyAF::Proxy::Derivative)).to eq true
        expect(subject.can?(:update, SpeedyAF::Proxy::Derivative)).to eq true
        expect(subject.can?(:destroy, SpeedyAF::Proxy::Derivative)).to eq true

        expect(subject.can?(:create, Admin::Collection)).to eq true
        expect(subject.can?(:read, Admin::Collection)).to eq true
        expect(subject.can?(:edit, Admin::Collection)).to eq true
        expect(subject.can?(:update, Admin::Collection)).to eq true
        expect(subject.can?(:destroy, Admin::Collection)).to eq true
        expect(subject.can?(:update_unit, Admin::Collection)).to eq true
        expect(subject.can?(:update_access_control, Admin::Collection)).to eq true
        expect(subject.can?(:update_managers, Admin::Collection)).to eq true
        expect(subject.can?(:update_editors, Admin::Collection)).to eq true
        expect(subject.can?(:update_depositors, Admin::Collection)).to eq true

        expect(subject.can?(:create, SpeedyAF::Proxy::Admin::Collection)).to eq true
        expect(subject.can?(:read, SpeedyAF::Proxy::Admin::Collection)).to eq true
        expect(subject.can?(:edit, SpeedyAF::Proxy::Admin::Collection)).to eq true
        expect(subject.can?(:update, SpeedyAF::Proxy::Admin::Collection)).to eq true
        expect(subject.can?(:destroy, SpeedyAF::Proxy::Admin::Collection)).to eq true
        expect(subject.can?(:update_unit, SpeedyAF::Proxy::Admin::Collection)).to eq true
        expect(subject.can?(:update_access_control, SpeedyAF::Proxy::Admin::Collection)).to eq true
        expect(subject.can?(:update_managers, SpeedyAF::Proxy::Admin::Collection)).to eq true
        expect(subject.can?(:update_editors, SpeedyAF::Proxy::Admin::Collection)).to eq true
        expect(subject.can?(:update_depositors, SpeedyAF::Proxy::Admin::Collection)).to eq true

        expect(subject.can?(:destroy, Admin::CollectionPresenter)).to eq true

        expect(subject.can?(:create, Admin::Unit)).to eq true
        expect(subject.can?(:read, Admin::Unit)).to eq true
        expect(subject.can?(:edit, Admin::Unit)).to eq true
        expect(subject.can?(:update, Admin::Unit)).to eq true
        expect(subject.can?(:destroy, Admin::Unit)).to eq true
        expect(subject.can?(:update_access_control, Admin::Unit)).to eq true
        expect(subject.can?(:update_unit_admins, Admin::Unit)).to eq true
        expect(subject.can?(:update_managers, Admin::Unit)).to eq true
        expect(subject.can?(:update_editors, Admin::Unit)).to eq true
        expect(subject.can?(:update_depositors, Admin::Unit)).to eq true

        expect(subject.can?(:create, SpeedyAF::Proxy::Admin::Unit)).to eq true
        expect(subject.can?(:read, SpeedyAF::Proxy::Admin::Unit)).to eq true
        expect(subject.can?(:edit, SpeedyAF::Proxy::Admin::Unit)).to eq true
        expect(subject.can?(:update, SpeedyAF::Proxy::Admin::Unit)).to eq true
        expect(subject.can?(:destroy, SpeedyAF::Proxy::Admin::Unit)).to eq true
        expect(subject.can?(:update_access_control, SpeedyAF::Proxy::Admin::Unit)).to eq true
        expect(subject.can?(:update_unit_admins, SpeedyAF::Proxy::Admin::Unit)).to eq true
        expect(subject.can?(:update_managers, SpeedyAF::Proxy::Admin::Unit)).to eq true
        expect(subject.can?(:update_editors, SpeedyAF::Proxy::Admin::Unit)).to eq true
        expect(subject.can?(:update_depositors, SpeedyAF::Proxy::Admin::Unit)).to eq true

        expect(subject.can?(:destroy, Admin::UnitPresenter)).to eq true
      end
    end
  end

  # UMD Customization
  describe '#user_groups' do
    context 'when options has an "access_token" entry' do
      it 'does not add "allow_download" group if the access token has expired' do
        # Only unexpired access tokens can be created
        access_token = FactoryBot.create(:access_token, expiration: 1.hour.from_now)
        access_token.allow_download = true
        access_token.save!
        expect(access_token.expired?).to be(false)

        travel_to(2.hours.from_now) do
          expect(access_token.expired?).to be(true)

          ability = Ability.new(nil, access_token: access_token.token)
          ability.options[:access_token] = access_token.token

          user_groups = ability.user_groups
          download_group_name = Ability.access_token_download_group_name(access_token.media_object_id)

          expect(user_groups.include?(download_group_name)).to be(false)
        end
      end

      let (:ability) { Ability.new(nil, { access_token: access_token.token }) }
      let (:access_token) { FactoryBot.create(:access_token) }

      it 'does not add "allow_download" group if the access token has been revoked' do
        access_token = FactoryBot.create(:access_token)

        access_token.revoked = true
        access_token.allow_download = true
        access_token.save!
        expect(access_token.revoked?).to be(true)

        user_groups = ability.user_groups
        download_group_name = Ability.access_token_download_group_name(access_token.media_object_id)

        expect(user_groups.include?(download_group_name)).to be(false)
      end

      it 'does not add "allow_download" group if the access token is active but downloads are not allowed' do
        expect(access_token.active?).to be(true)
        expect(access_token.allow_download?).to be(false)

        user_groups = ability.user_groups
        download_group_name = Ability.access_token_download_group_name(access_token.media_object_id)

        expect(user_groups.include?(download_group_name)).to be(false)
      end

      it 'does not add "allow_download" group if the access token does not exist' do
        ability = Ability.new(nil, { access_token: 'does_not_exist' })

        user_groups = ability.user_groups
        download_group_name = Ability.access_token_download_group_name(access_token.media_object_id)

        expect(user_groups.include?(download_group_name)).to be(false)
      end

      it 'adds an "allow_download" group if access token is active and allows downloads' do
        access_token.allow_download = true
        access_token.save!
        expect(access_token.active?).to be(true)
        expect(access_token.allow_download?).to be(true)

        user_groups = ability.user_groups
        download_group_name = Ability.access_token_download_group_name(access_token.media_object_id)

        expect(user_groups.include?(download_group_name)).to be(true)
      end
    end
  end

  describe 'masterfile_download Ability' do
    let(:published_media_object) { FactoryBot.create(:published_media_object) }
    let(:master_file) { FactoryBot.create(:master_file, media_object: published_media_object) }

    it 'is not available if master_file does not have associated media_object' do
      master_file = FactoryBot.create(:master_file)
      # Need to use "user" instead of "admin", because "admin" skips permissions
      # check.
      ability = Ability.new(FactoryBot.create(:user))
      expect(ability).to_not be_able_to(:master_file_download, master_file)
    end

    it 'is not available to non-logged in users' do
      ability = Ability.new(nil)
      expect(ability).to_not be_able_to(:master_file_download, master_file)
    end

    it 'is available to admin users' do
      ability = Ability.new(FactoryBot.create(:admin))
      expect(ability).to be_able_to(:master_file_download, master_file)
    end

    it 'is available to managers, editors, and depositors of the collection' do
      collection_users = master_file.media_object.collection.managers +
                        master_file.media_object.collection.editors +
                        master_file.media_object.collection.depositors
      collection_users.each do |user_name|
        ability = Ability.new(User.find_by(username: user_name))
        expect(ability).to be_able_to(:master_file_download, master_file)
      end
    end

    it 'is not available to managers, editors, and depositors of other collections' do
      other_collection = FactoryBot.create(:collection)

      other_collection_users = other_collection.managers +
                              other_collection.editors +
                              other_collection.depositors

      other_collection_users.each do |user_name|
        ability = Ability.new(User.find_by(username: user_name))
        expect(ability).to_not be_able_to(:master_file_download, master_file)
      end
    end

    it 'is available if an active access token allowing downloads is provided' do
      access_token = FactoryBot.create(:access_token)
      access_token.media_object_id = master_file.media_object.id
      access_token.allow_download = true
      access_token.save!

      token = access_token.token
      ability = Ability.new(nil, { access_token: token })
      expect(ability).to be_able_to(:master_file_download, master_file)
    end
  end

  # UMD Customization
  describe "read Ability for streaming reserve items" do
    context 'when media object is a streaming reserve' do
      let(:streaming_reserves_unit) { FactoryBot.create(:unit, name: Settings.streaming_reserves.unit_name) }
      let(:streaming_collection) { FactoryBot.create(:collection, unit: streaming_reserves_unit) }

      context 'and the media object is published' do
        let(:media_object) do
          FactoryBot.create(:published_media_object, collection: streaming_collection, visibility: 'private')
        end

        it 'is not readable by non-logged in users' do
          ability = Ability.new(nil)
          expect(ability).to_not be_able_to(:read, media_object)
        end

        it 'is not readable by ordinary logged in users without read access' do
          ability = Ability.new(FactoryBot.create(:user))
          expect(ability).to_not be_able_to(:read, media_object)
        end

        it 'is readable by users with read access (e.g., added to read_users)' do
          user = FactoryBot.create(:user)
          media_object.read_users += [user.user_key]
          media_object.save!
          ability = Ability.new(user)
          expect(ability).to be_able_to(:read, media_object)
        end

        it 'is readable by admin users' do
          ability = Ability.new(FactoryBot.create(:admin))
          expect(ability).to be_able_to(:read, media_object)
        end

        it 'is readable by managers, editors, and depositors of the collection' do
          collection_users = media_object.collection.managers +
                            media_object.collection.editors +
                            media_object.collection.depositors
          collection_users.each do |user_name|
            ability = Ability.new(User.find_by(username: user_name))
            expect(ability).to be_able_to(:read, media_object)
          end
        end
      end

      context 'and the media object is unpublished' do
        let(:media_object) do
          FactoryBot.create(:media_object, collection: streaming_collection)
        end

        it 'is not readable by non-logged in users' do
          ability = Ability.new(nil)
          expect(ability).to_not be_able_to(:read, media_object)
        end

        it 'is still readable by users with explicit read access even when unpublished (Hydra base permissions)' do
          user = FactoryBot.create(:user)
          media_object.read_users += [user.user_key]
          media_object.save!
          ability = Ability.new(user)
          expect(ability).to be_able_to(:read, media_object)
        end

        it 'is not readable by ordinary logged in users without read access' do
          ability = Ability.new(FactoryBot.create(:user))
          expect(ability).to_not be_able_to(:read, media_object)
        end

        it 'is readable by managers, editors, and depositors of the collection (via edit access)' do
          collection_users = media_object.collection.managers +
                            media_object.collection.editors +
                            media_object.collection.depositors
          collection_users.each do |user_name|
            ability = Ability.new(User.find_by(username: user_name))
            expect(ability).to be_able_to(:read, media_object)
          end
        end
      end
    end

    context 'when media object is NOT a streaming reserve (regression)' do
      let(:regular_collection) { FactoryBot.create(:collection) }

      context 'and the media object is published' do
        let(:media_object) do
          FactoryBot.create(:published_media_object, collection: regular_collection, visibility: 'private')
        end

        it 'is readable by non-logged in users even without read access' do
          ability = Ability.new(nil)
          expect(ability).to be_able_to(:read, media_object)
        end

        it 'is readable by ordinary logged in users without read access' do
          ability = Ability.new(FactoryBot.create(:user))
          expect(ability).to be_able_to(:read, media_object)
        end
      end

      context 'and discoverability is suppressed via item-level override' do
        let(:media_object) do
          mo = FactoryBot.create(:published_media_object, collection: regular_collection, visibility: 'private')
          mo.disable_inheritance = true
          mo.hidden = true
          mo.save!
          mo
        end

        it 'is not readable by non-logged in users' do
          ability = Ability.new(nil)
          expect(ability).to_not be_able_to(:read, media_object)
        end

        it 'is not readable by ordinary logged in users without read access' do
          ability = Ability.new(FactoryBot.create(:user))
          expect(ability).to_not be_able_to(:read, media_object)
        end

        it 'is still readable by admin users' do
          ability = Ability.new(FactoryBot.create(:admin))
          expect(ability).to be_able_to(:read, media_object)
        end

        it 'is still readable by managers, editors, and depositors of the collection' do
          collection_users = media_object.collection.managers +
                            media_object.collection.editors +
                            media_object.collection.depositors
          collection_users.each do |user_name|
            ability = Ability.new(User.find_by(username: user_name))
            expect(ability).to be_able_to(:read, media_object)
          end
        end

        it 'is readable by a user granted explicit read access (special access)' do
          user = FactoryBot.create(:user)
          media_object.read_users += [user.user_key]
          media_object.save!
          ability = Ability.new(user)
          expect(ability).to be_able_to(:read, media_object)
        end

        # Regression: "public"/"registered" are ambient Item Access, not an explicit
        # grant. Honouring them as one would make a public item impossible to hide.
        it 'is not readable by anonymous users even when its visibility is public' do
          media_object.visibility = 'public'
          media_object.save!
          ability = Ability.new(nil)
          expect(ability).to_not be_able_to(:read, media_object)
        end

        it 'is not readable by ordinary logged in users when its visibility is restricted' do
          media_object.visibility = 'restricted'
          media_object.save!
          ability = Ability.new(FactoryBot.create(:user))
          expect(ability).to_not be_able_to(:read, media_object)
        end

        it 'is readable by the holder of an active access token' do
          access_token = FactoryBot.create(:access_token, :allow_streaming, media_object_id: media_object.id)
          ability = Ability.new(nil, { access_token: access_token.token })
          expect(ability).to be_able_to(:read, media_object)
        end

        it 'is not readable with an access token for a different media object' do
          other_media_object = FactoryBot.create(:published_media_object, collection: regular_collection)
          access_token = FactoryBot.create(:access_token, :allow_streaming, media_object_id: other_media_object.id)
          ability = Ability.new(nil, { access_token: access_token.token })
          expect(ability).to_not be_able_to(:read, media_object)
        end
      end

      context 'and discoverability is suppressed via the collection default' do
        let(:hidden_collection) { FactoryBot.create(:collection, default_hidden: true) }
        let(:media_object) do
          FactoryBot.create(:published_media_object, collection: hidden_collection, visibility: 'public')
        end

        it 'is not readable by non-logged in users' do
          ability = Ability.new(nil)
          expect(ability).to_not be_able_to(:read, media_object)
        end

        it 'is not readable by ordinary logged in users without read access' do
          ability = Ability.new(FactoryBot.create(:user))
          expect(ability).to_not be_able_to(:read, media_object)
        end

        it 'is not readable when evaluated against the Solr-backed proxy' do
          media_object # ensure indexed
          proxy = SpeedyAF::Proxy::MediaObject.find(media_object.id)
          ability = Ability.new(nil)
          expect(ability).to_not be_able_to(:read, proxy)
        end

        it 'is still readable by admin users' do
          ability = Ability.new(FactoryBot.create(:admin))
          expect(ability).to be_able_to(:read, media_object)
        end

        it 'is readable by an item that has overridden inheritance and is not itself hidden' do
          media_object.disable_inheritance = true
          media_object.save!
          ability = Ability.new(nil)
          expect(ability).to be_able_to(:read, media_object)
        end
      end
    end
  end
  # End UMD Customization

  describe "stream Ability" do
    context 'when media object is unpublished' do
      let(:unpublished_media_object) { FactoryBot.create(:media_object) }

      it 'is not streamable by non-logged in users' do
        ability = Ability.new(nil)
        expect(ability).to_not be_able_to(:stream, unpublished_media_object)
      end

      it 'is not streamable by ordinary logged in users' do
        ability = Ability.new(FactoryBot.create(:user))
        expect(ability).to_not be_able_to(:stream, unpublished_media_object)
      end

      it 'is streamable by admin users' do
        ability = Ability.new(FactoryBot.create(:admin))
        expect(ability).to be_able_to(:stream, unpublished_media_object)
      end

      it 'is streamable by managers, editors, and depositors of the collection' do
        collection_users = unpublished_media_object.collection.managers +
                          unpublished_media_object.collection.editors +
                          unpublished_media_object.collection.depositors
        collection_users.each do |user_name|
          ability = Ability.new(User.find_by(username: user_name))
          expect(ability).to be_able_to(:stream, unpublished_media_object)
        end
      end

      it 'is not streamable by managers, editors, and depositors of other collections' do
        other_collection = FactoryBot.create(:collection)

        other_collection_users = other_collection.managers +
                                other_collection.editors +
                                other_collection.depositors

        other_collection_users.each do |user_name|
          ability = Ability.new(User.find_by(username: user_name))
          expect(ability).to_not be_able_to(:stream, unpublished_media_object)
        end
      end
    end

    context 'when media object is published' do
      let(:published_media_object) { FactoryBot.create(:published_media_object) }
      context 'and item access (visibility) is "private"' do
        before(:each) do
          published_media_object.visibility = 'private'
          published_media_object.save!
          published_media_object.reload
          expect(published_media_object.visibility).to eq('private')
        end

        it 'is not streamable by non-logged in users' do
          ability = Ability.new(nil)
          expect(ability).to_not be_able_to(:stream, published_media_object)
        end

        it 'is not streamable by ordinary logged in users' do
          ability = Ability.new(FactoryBot.create(:user))
          expect(ability).to_not be_able_to(:stream, published_media_object)
        end

        it 'is streamable by admin users' do
          ability = Ability.new(FactoryBot.create(:admin))
          expect(ability).to be_able_to(:stream, published_media_object)
        end

        it 'is streamable by managers, editors, and depositors of the collection' do
          collection_users = published_media_object.collection.managers +
                            published_media_object.collection.editors +
                            published_media_object.collection.depositors
          collection_users.each do |user_name|
            ability = Ability.new(User.find_by(username: user_name))
            expect(ability).to be_able_to(:stream, published_media_object)
          end
        end

        it 'is not streamable by managers, editors, and depositors of other collections' do
          other_collection = FactoryBot.create(:collection)

          other_collection_users = other_collection.managers +
                                  other_collection.editors +
                                  other_collection.depositors

          other_collection_users.each do |user_name|
            ability = Ability.new(User.find_by(username: user_name))
            expect(ability).to_not be_able_to(:stream, published_media_object)
          end
        end

        it 'is streamable if an active access token allowing streaming is provided' do
          access_token = FactoryBot.create(:access_token, :allow_streaming)
          access_token.media_object_id = published_media_object.id
          access_token.save!

          token = access_token.token
          ability = Ability.new(nil, { access_token: token })
          expect(ability).to be_able_to(:stream, published_media_object)
        end
      end

      context 'and item access (visibility) is "restricted" (to logged in users)' do
        before(:each) do
          published_media_object.visibility = 'restricted'
          published_media_object.save!
          published_media_object.reload
          expect(published_media_object.visibility).to eq('restricted')
        end

        it 'is not streamable by non-logged in users' do
          ability = Ability.new(nil)
          expect(ability).to_not be_able_to(:stream, published_media_object)
        end

        it 'is streamable by ordinary logged in users' do
          ability = Ability.new(FactoryBot.create(:user))
          expect(ability).to be_able_to(:stream, published_media_object)
        end

        it 'is streamable by admin users' do
          ability = Ability.new(FactoryBot.create(:admin))
          expect(ability).to be_able_to(:stream, published_media_object)
        end

        it 'is streamable by managers, editors, and depositors of the collection' do
          collection_users = published_media_object.collection.managers +
                            published_media_object.collection.editors +
                            published_media_object.collection.depositors
          collection_users.each do |user_name|
            ability = Ability.new(User.find_by(username: user_name))
            expect(ability).to be_able_to(:stream, published_media_object)
          end
        end

        it 'is streamable by managers, editors, and depositors of other collections' do
          other_collection = FactoryBot.create(:collection)

          other_collection_users = other_collection.managers +
                                  other_collection.editors +
                                  other_collection.depositors

          other_collection_users.each do |user_name|
            ability = Ability.new(User.find_by(username: user_name))
            expect(ability).to be_able_to(:stream, published_media_object)
          end
        end

        it 'is streamable if an active access token allowing streaming is provided' do
          access_token = FactoryBot.create(:access_token, :allow_streaming)
          access_token.media_object_id = published_media_object.id
          access_token.save!

          token = access_token.token
          ability = Ability.new(nil, { access_token: token })
          expect(ability).to be_able_to(:stream, published_media_object)
        end
      end

      context 'and item access (visibility) is "public"' do
        before(:each) do
          published_media_object.visibility = 'public'
          published_media_object.save!
          published_media_object.reload
          expect(published_media_object.visibility).to eq('public')
        end

        it 'is streamable by non-logged in users' do
          ability = Ability.new(nil)
          expect(ability).to be_able_to(:stream, published_media_object)
        end

        it 'is streamable by ordinary logged in users' do
          ability = Ability.new(FactoryBot.create(:user))
          expect(ability).to be_able_to(:stream, published_media_object)
        end

        it 'is streamable by admin users' do
          ability = Ability.new(FactoryBot.create(:admin))
          expect(ability).to be_able_to(:stream, published_media_object)
        end

        it 'is streamable by managers, editors, and depositors of the collection' do
          collection_users = published_media_object.collection.managers +
                            published_media_object.collection.editors +
                            published_media_object.collection.depositors
          collection_users.each do |user_name|
            ability = Ability.new(User.find_by(username: user_name))
            expect(ability).to be_able_to(:stream, published_media_object)
          end
        end

        it 'is streamable by managers, editors, and depositors of other collections' do
          other_collection = FactoryBot.create(:collection)

          other_collection_users = other_collection.managers +
                                  other_collection.editors +
                                  other_collection.depositors

          other_collection_users.each do |user_name|
            ability = Ability.new(User.find_by(username: user_name))
            expect(ability).to be_able_to(:stream, published_media_object)
          end
        end

        it 'is streamable if an active access token allowing streaming is provided' do
          access_token = FactoryBot.create(:access_token, :allow_streaming)
          access_token.media_object_id = published_media_object.id
          access_token.save!

          token = access_token.token
          ability = Ability.new(nil, { access_token: token })
          expect(ability).to be_able_to(:stream, published_media_object)
        end
      end
    end
  end

  describe '.course_reserves_collection' do
    let(:streaming_reserves_unit) { FactoryBot.create(:unit, name: Settings.streaming_reserves.unit_name) }
    let!(:course_reserves_collection) do
      FactoryBot.create(:collection, unit: streaming_reserves_unit)
    end
    let!(:regular_collection) { FactoryBot.create(:collection) }

    it 'returns the collection with streaming_reserves unit' do
      expect(Ability.course_reserves_collection).to eq(course_reserves_collection)
    end

    it 'returns nil if no course reserves collection exists' do
      course_reserves_collection.destroy
      expect(Ability.course_reserves_collection).to be_nil
    end

    it 'caches the result' do
      # First call should query
      result1 = Ability.course_reserves_collection
      expect(result1).to eq(course_reserves_collection)
      
      # Subsequent calls should use cached value
      expect(Admin::Collection).not_to receive(:all)
      result2 = Ability.course_reserves_collection
      expect(result2).to eq(course_reserves_collection)
    end
  end

  describe '.clear_course_reserves_collection_cache' do
    let(:streaming_reserves_unit) { FactoryBot.create(:unit, name: Settings.streaming_reserves.unit_name) }
    let!(:course_reserves_collection) do
      FactoryBot.create(:collection, unit: streaming_reserves_unit)
    end

    it 'clears the cached course reserves collection' do
      # Populate the cache
      Ability.course_reserves_collection
      
      # Clear the cache
      Ability.clear_course_reserves_collection_cache
      
      # Should query again
      expect(Admin::Collection).to receive(:all).and_call_original
      Ability.course_reserves_collection
    end

    it 'allows cache to be repopulated after clearing' do
      # Populate the cache
      first_result = Ability.course_reserves_collection
      expect(first_result).to eq(course_reserves_collection)
      
      # Clear the cache
      Ability.clear_course_reserves_collection_cache
      
      # Create a new course reserves collection with different name
      course_reserves_collection.destroy
      new_course_reserves_collection = FactoryBot.create(:collection,
        unit: streaming_reserves_unit,
        name: 'New Course Reserves')
      
      # Should return the new collection
      second_result = Ability.course_reserves_collection
      expect(second_result).to eq(new_course_reserves_collection)
      expect(second_result).not_to eq(first_result)
    end
  end

  describe '#is_course_reserves_manager?' do
    let(:user) { FactoryBot.create(:user) }
    let(:manager) { FactoryBot.create(:manager) }
    let(:streaming_reserves_unit) { FactoryBot.create(:unit, name: Settings.streaming_reserves.unit_name) }
    let!(:course_reserves_collection) do
      FactoryBot.create(:collection,
        unit: streaming_reserves_unit,
        managers: [manager.user_key])
    end

    it 'returns true for course reserves collection managers' do
      ability = Ability.new(manager)
      expect(ability.is_course_reserves_manager?).to be true
    end

    it 'returns false for non-managers' do
      ability = Ability.new(user)
      expect(ability.is_course_reserves_manager?).to be false
    end

    it 'returns false when no course reserves collection exists' do
      course_reserves_collection.destroy
      Ability.clear_course_reserves_collection_cache
      ability = Ability.new(manager)
      expect(ability.is_course_reserves_manager?).to be false
    end
  end

  describe '#is_course_reserves_member?' do
    let(:user) { FactoryBot.create(:user) }
    let(:manager) { FactoryBot.create(:manager) }
    let(:editor) { FactoryBot.create(:user) }
    let(:depositor) { FactoryBot.create(:user) }
    let(:streaming_reserves_unit) { FactoryBot.create(:unit, name: Settings.streaming_reserves.unit_name) }
    let!(:course_reserves_collection) do
      FactoryBot.create(:collection,
        unit: streaming_reserves_unit,
        managers: [manager.user_key],
        editors: [editor.user_key],
        depositors: [depositor.user_key])
    end

    it 'returns true for course reserves collection managers' do
      ability = Ability.new(manager)
      expect(ability.is_course_reserves_member?).to be true
    end

    it 'returns true for course reserves collection editors' do
      ability = Ability.new(editor)
      expect(ability.is_course_reserves_member?).to be true
    end

    it 'returns true for course reserves collection depositors' do
      ability = Ability.new(depositor)
      expect(ability.is_course_reserves_member?).to be true
    end

    it 'returns false for non-members' do
      ability = Ability.new(user)
      expect(ability.is_course_reserves_member?).to be false
    end

    it 'returns false when no course reserves collection exists' do
      course_reserves_collection.destroy
      Ability.clear_course_reserves_collection_cache
      ability = Ability.new(manager)
      expect(ability.is_course_reserves_member?).to be false
    end

    it 'returns true for administrators' do
      admin = FactoryBot.create(:admin)
      ability = Ability.new(admin)
      expect(ability.is_course_reserves_member?).to be true
    end
  end

  describe 'full_read Ability with disable_inheritance (UMD Customization)' do
    # UMD changed `cannot :read` to `cannot :full_read` so that users who are
    # exclusively inherited from a parent collection (and whose access is blocked
    # by disable_inheritance) can still :read (discover/view) a published item,
    # while being denied the more permissive :full_read (supplemental files, etc.).
    let(:collection) { FactoryBot.create(:collection) }
    let(:user) { FactoryBot.create(:user) }

    let(:media_object) do
      mo = FactoryBot.create(:published_media_object, collection: collection)
      mo.disable_inheritance = true
      mo.save!
      mo
    end

    before do
      # Add the user to the collection's default_read_users so they appear in
      # media_object.inherited_read_users but NOT in media_object.read_users.
      # The user is deliberately NOT added as a manager/editor/depositor.
      collection.default_read_users += [user.user_key]
      collection.save!
    end

    context 'when the media object is published and disable_inheritance is set' do
      it 'allows :read for a user with only inherited access (UMD: not blocked like upstream)' do
        ability = Ability.new(user)
        expect(ability).to be_able_to(:read, media_object)
      end

      it 'denies :full_read for a user with only inherited access' do
        ability = Ability.new(user)
        expect(ability).not_to be_able_to(:full_read, media_object)
      end

      it 'allows :full_read for a collection manager even with disable_inheritance' do
        manager_user = User.find_by(username: collection.managers.first)
        ability = Ability.new(manager_user)
        expect(ability).to be_able_to(:full_read, media_object)
      end

      it 'allows :full_read for an admin regardless of disable_inheritance' do
        admin = FactoryBot.create(:admin)
        ability = Ability.new(admin)
        expect(ability).to be_able_to(:full_read, media_object)
      end
    end

    context 'when disable_inheritance is not set' do
      let(:media_object_without_flag) do
        FactoryBot.create(:published_media_object, collection: collection)
      end

      it 'allows :full_read because the cannot block does not apply' do
        # With disable_inheritance false, Hydra checks the governing policy
        # (collection), finds the user in inheritable_read_access_person_ssim,
        # and grants read access. The cannot :full_read block short-circuits on
        # disable_inheritance? being false and does not restrict access.
        ability = Ability.new(user)
        expect(media_object_without_flag.disable_inheritance?).to be false
        expect(ability).to be_able_to(:full_read, media_object_without_flag)
      end
    end
  end
  # End UMD Customization
end
