FactoryBot.define do
  factory :access_token do
    # Have an admin user by default, so token will be valid for any media object
    association :user, factory: :admin
    media_object_id { FactoryBot.create(:media_object).id }
    expiration { 7.days.from_now }

    trait :allow_streaming do
      allow_streaming { true }
    end
  end
end
