FactoryBot.define do
  factory :escalated_automation, class: "Escalated::Automation" do
    name { "#{Faker::Hacker.verb.capitalize} Automation" }
    active { true }
    position { rand(1..20) }

    conditions do
      [
        { "field" => "status", "operator" => "equals", "value" => "open" },
        { "field" => "priority", "operator" => "equals", "value" => "urgent" }
      ]
    end

    actions do
      [
        { "type" => "assign_department", "value" => "support" },
        { "type" => "add_tag", "value" => "auto-assigned" }
      ]
    end

    trait :inactive do
      active { false }
    end

    trait :with_notification do
      actions do
        [
          { "type" => "send_notification", "value" => "admin@example.com" },
          { "type" => "change_priority", "value" => "high" }
        ]
      end
    end
  end
end
