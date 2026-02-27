FactoryBot.define do
  factory :escalated_webhook, class: "Escalated::Webhook" do
    url { Faker::Internet.url(scheme: "https") }
    secret { SecureRandom.hex(20) }
    active { true }
    events { %w[ticket.created ticket.updated ticket.resolved] }

    trait :inactive do
      active { false }
    end

    trait :all_events do
      events do
        %w[
          ticket.created ticket.updated ticket.resolved ticket.closed
          ticket.assigned reply.created note.created
        ]
      end
    end

    trait :with_deliveries do
      after(:create) do |webhook|
        create_list(:escalated_webhook_delivery, 3, webhook: webhook)
      end
    end
  end

  factory :escalated_webhook_delivery, class: "Escalated::WebhookDelivery" do
    event { "ticket.created" }
    response_code { 200 }
    payload { { ticket_id: rand(1..100), event: "ticket.created" } }
    response_body { '{"ok":true}' }
    attempts { 1 }
    association :webhook, factory: :escalated_webhook

    trait :failed do
      response_code { 500 }
      response_body { '{"error":"Internal Server Error"}' }
    end

    trait :timeout do
      response_code { nil }
      response_body { nil }
      attempts { 3 }
    end
  end
end
