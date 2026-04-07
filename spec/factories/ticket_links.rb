# frozen_string_literal: true

FactoryBot.define do
  factory :escalated_ticket_link, class: 'Escalated::TicketLink' do
    link_type { 'related' }
    association :parent_ticket, factory: :escalated_ticket
    association :child_ticket, factory: :escalated_ticket

    trait :problem_incident do
      link_type { 'problem_incident' }
    end

    trait :parent_child do
      link_type { 'parent_child' }
    end
  end
end
