FactoryBot.define do
  factory :escalated_article, class: "Escalated::Article" do
    title { Faker::Lorem.unique.sentence(word_count: 5) }
    slug { title&.parameterize }
    body { Faker::Lorem.paragraphs(number: 3).join("\n\n") }
    status { "draft" }
    association :category, factory: :escalated_article_category
    association :author, factory: :user

    trait :published do
      status { "published" }
    end

    trait :archived do
      status { "archived" }
    end

    trait :without_category do
      category { nil }
    end
  end
end
