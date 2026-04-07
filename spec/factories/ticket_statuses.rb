# frozen_string_literal: true

FactoryBot.define do
  factory :escalated_ticket_status, class: 'Escalated::TicketStatus' do
    label { Faker::Lorem.unique.word.capitalize }
    category { %w[open pending resolved closed].sample }
    color { Faker::Color.hex_color }
    position { rand(1..20) }
    is_default { false }

    trait :default do
      is_default { true }
    end

    trait :open_category do
      category { 'open' }
    end

    trait :pending_category do
      category { 'pending' }
    end

    trait :resolved_category do
      category { 'resolved' }
    end

    trait :closed_category do
      category { 'closed' }
    end
  end
end
