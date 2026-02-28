FactoryBot.define do
  factory :escalated_custom_object, class: "Escalated::CustomObject" do
    name { Faker::Commerce.unique.product_name }
    slug { name&.parameterize(separator: "_") }

    fields_schema do
      [
        { "name" => "name", "type" => "text", "required" => true },
        { "name" => "value", "type" => "text", "required" => false }
      ]
    end

    trait :with_records do
      after(:create) do |definition|
        create_list(:escalated_custom_object_record, 3, object: definition)
      end
    end

    trait :complex_schema do
      fields_schema do
        [
          { "name" => "name", "type" => "text", "required" => true },
          { "name" => "email", "type" => "email", "required" => false },
          { "name" => "priority", "type" => "dropdown", "required" => false, "options" => %w[low medium high] },
          { "name" => "is_active", "type" => "boolean", "required" => false },
          { "name" => "created_date", "type" => "date", "required" => false }
        ]
      end
    end
  end

  factory :escalated_custom_object_record, class: "Escalated::CustomObjectRecord" do
    data { { "name" => Faker::Company.name, "value" => Faker::Lorem.word } }
    association :object, factory: :escalated_custom_object
  end
end
