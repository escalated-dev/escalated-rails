# frozen_string_literal: true

FactoryBot.define do
  factory :escalated_side_conversation, class: 'Escalated::SideConversation' do
    subject { Faker::Lorem.sentence(word_count: 5) }
    channel { 'email' }
    status { 'open' }
    association :ticket, factory: :escalated_ticket
    association :created_by, factory: :user

    trait :closed do
      status { 'closed' }
    end

    trait :via_slack do
      channel { 'slack' }
    end

    trait :via_phone do
      channel { 'phone' }
    end

    trait :with_replies do
      after(:create) do |conversation|
        create_list(:escalated_side_conversation_reply, 2, side_conversation: conversation)
      end
    end
  end

  factory :escalated_side_conversation_reply, class: 'Escalated::SideConversationReply' do
    body { Faker::Lorem.paragraph(sentence_count: 2) }
    association :side_conversation, factory: :escalated_side_conversation
    association :author, factory: :user

    trait :inbound do
      # no direction column; trait kept for compatibility
    end
  end
end
