# frozen_string_literal: true

FactoryBot.define do
  factory :escalated_contact, class: 'Escalated::Contact' do
    sequence(:email) { |n| "contact#{n}@example.com" }
    name { Faker::Name.name }
    user_id { nil }
    metadata { {} }
  end
end
