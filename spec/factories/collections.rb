# Copyright 2011-2022, The Trustees of Indiana University and Northwestern
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

FactoryBot.define do
  factory :collection, class: Admin::Collection do
    sequence(:name) {|n| "Collection #{n}" }
    unit {"Default Unit"}
    description {Faker::Lorem.sentence}
    contact_email { Faker::Internet.email }
    website_label { Faker::Lorem.words.join(' ') }
    website_url { Faker::Internet.url }
    managers {[FactoryBot.create(:manager).user_key]}
    editors {[FactoryBot.create(:user).user_key]}
    depositors {[FactoryBot.create(:user).user_key]}
    media_objects {[]}

    transient { items { 0 } }
    after(:create) do |c, env|
      1.upto(env.items) { FactoryBot.create(:media_object, collection: c) }
      c.reload
    end

    trait :with_poster do
      after(:build) do |collection|
        collection.poster.mime_type = 'image/png'
        collection.poster.content = 'fake image content'
        collection.save
      end
    end

    trait :with_manager do
      transient do
        manager {nil}
      end
      after(:build) do |collection, evaluator|
        if evaluator.manager.present?
          collection.add_manager(evaluator.manager.user_key)
        end
      end
    end

    trait :with_editor do
      transient do
        editor {nil}
      end
      after(:build) do |collection, evaluator|
        if evaluator.editor.present?
          collection.add_editor(evaluator.editor.user_key)
        end
      end
    end

    trait :with_depositor do
      transient do
        depositor {nil}
      end
      after(:build) do |collection, evaluator|
        if evaluator.depositor.present?
          collection.add_depositor(evaluator.depositor.user_key)
        end
      end
    end
  end
end
