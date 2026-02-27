FactoryBot.define do
  factory :escalated_audit_log, class: "Escalated::AuditLog" do
    action { %w[create update destroy login logout].sample }
    association :auditable, factory: :escalated_ticket
    old_values { { "status" => "open" } }
    new_values { { "status" => "in_progress" } }
    ip_address { Faker::Internet.ip_v4_address }
    user_agent { Faker::Internet.user_agent }
    association :user, factory: :user

    trait :ticket_action do
      auditable_type { "Escalated::Ticket" }
      action { %w[create update status_change assignment].sample }
    end

    trait :login do
      action { "login" }
      auditable_type { nil }
      auditable_id { nil }
      old_values { {} }
      new_values { {} }
    end

    trait :destroy_action do
      action { "destroy" }
      old_values { {} }
      new_values { {} }
    end
  end
end
