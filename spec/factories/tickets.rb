FactoryBot.define do
  factory :escalated_ticket, class: "Escalated::Ticket" do
    subject { Faker::Lorem.sentence(word_count: 6) }
    description { Faker::Lorem.paragraph(sentence_count: 3) }
    status { :open }
    priority { :medium }
    reference { Escalated::Ticket.generate_reference }
    association :requester, factory: :user
    metadata { {} }

    trait :with_assignee do
      association :assignee, factory: :user
      assigned_to { assignee.id }
      status { :in_progress }
    end

    trait :with_department do
      association :department, factory: :escalated_department
    end

    trait :with_sla do
      association :sla_policy, factory: :escalated_sla_policy
      sla_first_response_due_at { 4.hours.from_now }
      sla_resolution_due_at { 24.hours.from_now }
    end

    trait :low_priority do
      priority { :low }
    end

    trait :high_priority do
      priority { :high }
    end

    trait :urgent do
      priority { :urgent }
    end

    trait :critical do
      priority { :critical }
    end

    trait :open do
      status { :open }
    end

    trait :in_progress do
      status { :in_progress }
    end

    trait :waiting_on_customer do
      status { :waiting_on_customer }
    end

    trait :waiting_on_agent do
      status { :waiting_on_agent }
    end

    trait :escalated do
      status { :escalated }
    end

    trait :resolved do
      status { :resolved }
      resolved_at { Time.current }
    end

    trait :closed do
      status { :closed }
      resolved_at { 2.days.ago }
      closed_at { Time.current }
    end

    trait :sla_breached do
      sla_breached { true }
      sla_first_response_due_at { 2.hours.ago }
    end
  end
end
