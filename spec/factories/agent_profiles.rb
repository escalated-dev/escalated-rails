FactoryBot.define do
  factory :escalated_agent_profile, class: "Escalated::AgentProfile" do
    association :user, factory: :user
    agent_type { "full" }
    max_tickets { 10 }

    trait :light do
      agent_type { "light" }
    end
  end
end
