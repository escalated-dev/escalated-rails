# frozen_string_literal: true

FactoryBot.define do
  factory :escalated_chat_session, class: 'Escalated::ChatSession' do
    association :ticket, factory: :escalated_ticket
    customer_session_id { SecureRandom.hex(16) }
    status { 'waiting' }

    trait :waiting do
      status { 'waiting' }
    end

    trait :active do
      status { 'active' }
      association :agent, factory: :user
      started_at { Time.current }
    end

    trait :ended do
      status { 'ended' }
      association :agent, factory: :user
      started_at { 30.minutes.ago }
      ended_at { Time.current }
    end

    trait :with_rating do
      rating { 4 }
      rating_comment { 'Great support!' }
    end
  end
end
