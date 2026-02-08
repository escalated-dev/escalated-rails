FactoryBot.define do
  factory :escalated_tag, class: "Escalated::Tag" do
    name { Faker::Lorem.unique.word.capitalize }
    slug { name&.parameterize }
    color { Faker::Color.hex_color }
    description { Faker::Lorem.sentence }
  end
end
