FactoryBot.define do
  factory :escalated_custom_field, class: "Escalated::CustomField" do
    name { Faker::Lorem.unique.words(number: 2).map(&:capitalize).join(" ") }
    field_type { "text" }
    context { "ticket" }
    position { rand(1..20) }
    required { false }
    description { Faker::Lorem.sentence }
    options { [] }

    trait :required do
      required { true }
    end

    trait :select do
      field_type { "select" }
      options { ["Option A", "Option B", "Option C"] }
    end

    trait :checkbox do
      field_type { "checkbox" }
    end

    trait :date do
      field_type { "date" }
    end

    trait :number do
      field_type { "number" }
    end

    trait :for_user do
      context { "user" }
    end

    trait :for_organization do
      context { "organization" }
    end
  end
end
