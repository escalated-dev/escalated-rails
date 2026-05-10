# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    name { Faker::Name.name }
    email { Faker::Internet.unique.email }
    role { 'customer' }

    trait :agent do
      role { 'agent' }
      is_agent { true }
    end

    trait :admin do
      role { 'admin' }
      is_admin { true }
      is_agent { true }
    end
  end
end
