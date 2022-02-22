FactoryBot.define do
  factory :access_token do
    association :user
    media_object_id { FactoryBot.create(:media_object).id }
    expiration { 7.days.from_now }
  end
end
