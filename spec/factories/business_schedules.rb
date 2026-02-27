FactoryBot.define do
  factory :escalated_business_schedule, class: "Escalated::BusinessSchedule" do
    name { "#{Faker::Company.name} Hours" }
    timezone { "UTC" }

    schedule do
      {
        "monday" => { "enabled" => true, "start" => "09:00", "end" => "17:00" },
        "tuesday" => { "enabled" => true, "start" => "09:00", "end" => "17:00" },
        "wednesday" => { "enabled" => true, "start" => "09:00", "end" => "17:00" },
        "thursday" => { "enabled" => true, "start" => "09:00", "end" => "17:00" },
        "friday" => { "enabled" => true, "start" => "09:00", "end" => "17:00" },
        "saturday" => { "enabled" => false, "start" => "09:00", "end" => "17:00" },
        "sunday" => { "enabled" => false, "start" => "09:00", "end" => "17:00" }
      }
    end

    trait :with_holidays do
      after(:create) do |schedule|
        create_list(:escalated_holiday, 2, schedule: schedule)
      end
    end

    trait :us_eastern do
      timezone { "America/New_York" }
    end

    trait :extended_hours do
      schedule do
        {
          "monday" => { "enabled" => true, "start" => "08:00", "end" => "20:00" },
          "tuesday" => { "enabled" => true, "start" => "08:00", "end" => "20:00" },
          "wednesday" => { "enabled" => true, "start" => "08:00", "end" => "20:00" },
          "thursday" => { "enabled" => true, "start" => "08:00", "end" => "20:00" },
          "friday" => { "enabled" => true, "start" => "08:00", "end" => "20:00" },
          "saturday" => { "enabled" => true, "start" => "10:00", "end" => "16:00" },
          "sunday" => { "enabled" => false, "start" => "09:00", "end" => "17:00" }
        }
      end
    end
  end

  factory :escalated_holiday, class: "Escalated::Holiday" do
    name { Faker::Lorem.word.capitalize }
    date { Faker::Date.forward(days: 365) }
    association :schedule, factory: :escalated_business_schedule
  end
end
