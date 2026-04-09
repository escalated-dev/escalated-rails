# frozen_string_literal: true

FactoryBot.define do
  factory :escalated_workflow, class: 'Escalated::Workflow' do
    name { Faker::Lorem.sentence(word_count: 3) }
    trigger_event { 'ticket.created' }
    conditions { { 'all' => [{ 'field' => 'status', 'operator' => 'equals', 'value' => 'open' }] } }
    actions { [{ 'type' => 'change_priority', 'value' => 'high' }] }
    is_active { true }
    position { 0 }
  end

  factory :escalated_workflow_log, class: 'Escalated::WorkflowLog' do
    association :workflow, factory: :escalated_workflow
    association :ticket, factory: :escalated_ticket
    trigger_event { 'ticket.created' }
    status { 'success' }
    actions_executed { [] }
  end

  factory :escalated_delayed_action, class: 'Escalated::DelayedAction' do
    association :workflow, factory: :escalated_workflow
    association :ticket, factory: :escalated_ticket
    action_data { { 'type' => 'change_status', 'value' => 'resolved' } }
    execute_at { 1.hour.from_now }
    executed { false }
  end
end
