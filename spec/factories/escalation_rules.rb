FactoryBot.define do
  factory :escalated_escalation_rule, class: "Escalated::EscalationRule" do
    name { "#{Faker::Hacker.verb.capitalize} Escalation Rule" }
    description { Faker::Lorem.sentence }
    is_active { true }
    priority { 0 }

    conditions do
      {
        "status" => ["open", "in_progress"],
        "priority" => ["high", "urgent", "critical"],
        "sla_breached" => true
      }
    end

    actions do
      {
        "change_status" => "escalated",
        "send_notification" => true,
        "add_internal_note" => "Auto-escalated due to SLA breach"
      }
    end

    trait :inactive do
      is_active { false }
    end

    trait :unassigned_timeout do
      conditions do
        {
          "status" => ["open"],
          "unassigned_for_minutes" => 30
        }
      end

      actions do
        {
          "change_priority" => "high",
          "send_notification" => true,
          "add_internal_note" => "Auto-escalated: unassigned for 30 minutes"
        }
      end
    end

    trait :no_response_timeout do
      conditions do
        {
          "no_response_for_minutes" => 60
        }
      end

      actions do
        {
          "change_status" => "escalated",
          "change_priority" => "urgent",
          "send_notification" => true,
          "notification_recipients" => ["escalation@example.com"],
          "add_tags" => ["escalated", "no-response"],
          "add_internal_note" => "Auto-escalated: no response for 60 minutes"
        }
      end
    end
  end
end
