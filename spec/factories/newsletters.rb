# frozen_string_literal: true

FactoryBot.define do
  factory :escalated_newsletter_list, class: 'Escalated::NewsletterList' do
    sequence(:name) { |n| "Newsletter list #{n}" }
    description { 'Newsletter recipients' }
    kind { 'static' }
    filter_json { nil }
    created_by { nil }

    trait :dynamic do
      kind { 'dynamic' }
      filter_json { { 'rules' => [] } }
    end
  end

  factory :escalated_newsletter_list_member, class: 'Escalated::NewsletterListMember' do
    association :list, factory: :escalated_newsletter_list
    association :contact, factory: :escalated_contact
    added_by { nil }
  end

  factory :escalated_newsletter_template, class: 'Escalated::NewsletterTemplate' do
    sequence(:name) { |n| "Template #{n}" }
    theme { 'default' }
    subject_template { 'Hello {{ contact.first_name }}' }
    body_markdown { '# Hello' }
    merge_fields_schema { {} }
    created_by { nil }
  end

  factory :escalated_newsletter, class: 'Escalated::Newsletter' do
    sequence(:subject) { |n| "Newsletter #{n}" }
    from_email { 'news@example.com' }
    from_name { 'News Team' }
    reply_to { 'reply@example.com' }
    association :target_list, factory: :escalated_newsletter_list
    template { nil }
    theme { 'default' }
    body_markdown { 'Hello {{ contact.first_name }}' }
    status { 'draft' }
    scheduled_at { nil }
    created_by { nil }
  end

  factory :escalated_newsletter_delivery, class: 'Escalated::NewsletterDelivery' do
    association :newsletter, factory: :escalated_newsletter
    association :contact, factory: :escalated_contact
    email_at_send { contact.email }
    status { 'pending' }
    sequence(:tracking_token) { |n| "token#{n}#{SecureRandom.hex(16)}"[0, 40] }
    attempt_count { 0 }
    is_test { false }
    created_at { Time.current }
  end
end
