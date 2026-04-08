# frozen_string_literal: true

FactoryBot.define do
  factory :escalated_chat_routing_rule, class: 'Escalated::ChatRoutingRule' do
    routing_strategy { 'round_robin' }
    offline_behavior { 'show_form' }
    max_queue_size { 50 }
    max_concurrent_per_agent { 5 }
    auto_close_after_minutes { 30 }
    is_active { true }
    position { 0 }

    trait :with_department do
      association :department, factory: :escalated_department
    end

    trait :least_busy do
      routing_strategy { 'least_busy' }
    end

    trait :inactive do
      is_active { false }
    end
  end
end
