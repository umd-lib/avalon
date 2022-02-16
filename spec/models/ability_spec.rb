# Copyright 2011-2020, The Trustees of Indiana University and Northwestern
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
    other_collection = FactoryBot.build(:collection)

    other_collection_users = other_collection.managers +
                             other_collection.editors +
                             other_collection.depositors

    other_collection_users.each do |user_name|
      ability = Ability.new(User.find_by(username: user_name))
      expect(ability).to_not be_able_to(:master_file_download, master_file)
    end
  end
end
