FactoryBot.define do
  factory :escalated_canned_response, class: "Escalated::CannedResponse" do
    title { Faker::Lorem.sentence(word_count: 4) }
    body { Faker::Lorem.paragraph(sentence_count: 3) }
    shortcode { Faker::Internet.unique.slug(glue: "_") }
    category { %w[greeting closing troubleshooting billing general].sample }
    is_shared { true }
    association :creator, factory: :user

    trait :personal do
      is_shared { false }
    end

    trait :with_variables do
      body { "Hello {{ticket.requester_name}},\n\nThank you for contacting us about {{ticket.subject}}.\n\nBest regards,\n{{agent.name}}" }
    end

    trait :greeting do
      title { "Standard Greeting" }
      shortcode { "greeting" }
      category { "greeting" }
      body { "Hello {{ticket.requester_name}},\n\nThank you for reaching out to our support team. We've received your request and will get back to you shortly." }
    end

    trait :closing do
      title { "Standard Closing" }
      shortcode { "closing" }
      category { "closing" }
      body { "If you have any further questions, please don't hesitate to reach out. We're here to help!\n\nBest regards,\n{{agent.name}}" }
    end
  end
end
