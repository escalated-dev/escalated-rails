# frozen_string_literal: true

FactoryBot.define do
  factory :escalated_mention, class: 'Escalated::Mention' do
    association :reply, factory: :escalated_reply
    association :user, factory: :user
    read_at { nil }
  end
end
