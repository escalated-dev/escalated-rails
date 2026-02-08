FactoryBot.define do
  factory :escalated_reply, class: "Escalated::Reply" do
    body { Faker::Lorem.paragraph(sentence_count: 2) }
    is_internal { false }
    is_system { false }
    association :ticket, factory: :escalated_ticket
    association :author, factory: :user

    trait :internal do
      is_internal { true }
    end

    trait :system do
      is_system { true }
      author { nil }
    end

    trait :with_attachments do
      after(:create) do |reply|
        create_list(:escalated_attachment, 2, attachable: reply)
      end
    end
  end
end
