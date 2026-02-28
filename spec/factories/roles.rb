FactoryBot.define do
  factory :escalated_role, class: "Escalated::Role" do
    name { Faker::Job.unique.title }
    description { Faker::Lorem.sentence }
    is_system { false }

    trait :system do
      is_system { true }
    end

    trait :agent_role do
      name { "Agent" }
      is_system { true }
    end

    trait :admin_role do
      name { "Administrator" }
      is_system { true }
    end

    trait :with_permissions do
      after(:create) do |role|
        create_list(:escalated_permission, 3, roles: [role])
      end
    end
  end

  factory :escalated_permission, class: "Escalated::Permission" do
    name { "#{Faker::Hacker.verb.capitalize} #{Faker::Hacker.noun}" }
    slug { name&.parameterize(separator: "_") }
    description { Faker::Lorem.sentence }
    group { %w[tickets departments users reports settings].sample }
  end
end
