# Copyright 2011-2023, The Trustees of Indiana University and Northwestern
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
require "cancan/matchers"

describe Ability, type: :model do
  describe 'non-logged in users' do
    it 'only belongs to the public group' do
      expect(Ability.new(nil).user_groups).to eq ["public"]
    end
  end

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

  describe "stream Ability" do
    context 'when media object is unpublished' do
      let(:unpublished_media_object) { FactoryBot.create(:media_object) }

      it 'is not streamable by non-logged in users' do
        ability = Ability.new(nil)
        expect(ability).to_not be_able_to(:stream, unpublished_media_object)
      end

      it 'is not streamable by ordinary logged in users' do
        ability = Ability.new(FactoryBot.create(:public))
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

      it 'is not streamable even if an active access token allowing streaming is provided' do
        # Access token does not allow streaming because media object is unpublished
        access_token = FactoryBot.create(:access_token, :allow_streaming)
        access_token.media_object_id = unpublished_media_object.id
        access_token.save!

        token = access_token.token
        ability = Ability.new(nil, { access_token: token })
        expect(ability).to_not be_able_to(:stream, unpublished_media_object)
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
          ability = Ability.new(FactoryBot.create(:public))
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
          ability = Ability.new(FactoryBot.create(:public))
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
          ability = Ability.new(FactoryBot.create(:public))
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
end