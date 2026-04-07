# frozen_string_literal: true

FactoryBot.define do
  factory :escalated_agent_capacity, class: 'Escalated::AgentCapacity' do
    max_concurrent { 5 }
    current_count { 0 }
    channel { 'default' }
    association :user, factory: :user

    trait :at_capacity do
      current_count { 5 }
    end

    trait :high_capacity do
      max_concurrent { 20 }
    end

    trait :busy do
      max_concurrent { 5 }
      current_count { rand(3..5) }
    end
  end
end
