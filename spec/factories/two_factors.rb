FactoryBot.define do
  factory :escalated_two_factor, class: "Escalated::TwoFactor" do
    secret { SecureRandom.base64(20) }
    recovery_codes { Array.new(8) { SecureRandom.hex(4) } }
    confirmed_at { 1.day.ago }
    association :user, factory: :user

    trait :unconfirmed do
      confirmed_at { nil }
    end

    trait :recently_confirmed do
      confirmed_at { 1.hour.ago }
    end
  end
end
