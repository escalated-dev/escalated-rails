# frozen_string_literal: true

FactoryBot.define do
  factory :escalated_article_category, class: 'Escalated::ArticleCategory' do
    name { Faker::Commerce.unique.department(max: 1) }
    slug { name&.parameterize }
    description { Faker::Lorem.sentence }
    position { rand(1..20) }

    trait :with_articles do
      after(:create) do |category|
        create_list(:escalated_article, 3, category: category)
      end
    end
  end
end
