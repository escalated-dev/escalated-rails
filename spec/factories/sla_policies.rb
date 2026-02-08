FactoryBot.define do
  factory :escalated_sla_policy, class: "Escalated::SlaPolicy" do
    name { "#{Faker::Company.buzzword.capitalize} SLA" }
    description { Faker::Lorem.sentence }
    is_active { true }
    is_default { false }

    first_response_hours do
      {
        "low" => 24,
        "medium" => 8,
        "high" => 4,
        "urgent" => 2,
        "critical" => 1
      }
    end

    resolution_hours do
      {
        "low" => 72,
        "medium" => 48,
        "high" => 24,
        "urgent" => 8,
        "critical" => 4
      }
    end

    trait :default do
      is_default { true }
    end

    trait :inactive do
      is_active { false }
    end

    trait :strict do
      first_response_hours do
        {
          "low" => 8,
          "medium" => 4,
          "high" => 2,
          "urgent" => 1,
          "critical" => 0.5
        }
      end

      resolution_hours do
        {
          "low" => 24,
          "medium" => 16,
          "high" => 8,
          "urgent" => 4,
          "critical" => 2
        }
      end
    end
  end
end
