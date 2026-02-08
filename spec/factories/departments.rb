FactoryBot.define do
  factory :escalated_department, class: "Escalated::Department" do
    name { Faker::Commerce.unique.department(max: 1) }
    slug { name&.parameterize }
    description { Faker::Lorem.sentence }
    email { Faker::Internet.email }
    is_active { true }

    trait :inactive do
      is_active { false }
    end

    trait :with_sla_policy do
      association :default_sla_policy, factory: :escalated_sla_policy
    end

    trait :with_agents do
      after(:create) do |department|
        agents = create_list(:user, 3)
        department.agents = agents
      end
    end
  end
end
