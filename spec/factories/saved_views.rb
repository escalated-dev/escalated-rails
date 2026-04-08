# frozen_string_literal: true

FactoryBot.define do
  factory :escalated_saved_view, class: 'Escalated::SavedView' do
    name { Faker::Lorem.sentence(word_count: 3) }
    filters { { 'status' => 'open', 'priority' => 'high' } }
    association :user, factory: :user
    is_shared { false }
    is_default { false }
    position { 0 }

    trait :shared do
      is_shared { true }
    end

    trait :default_view do
      is_default { true }
    end
  end
end
