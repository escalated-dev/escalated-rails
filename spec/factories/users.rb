FactoryBot.define do
  factory :user do
    name { Faker::Name.name }
    email { Faker::Internet.unique.email }
    role { "customer" }

    trait :agent do
      role { "agent" }
    end

    trait :admin do
      role { "admin" }
    end
  end
end
