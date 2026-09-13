# frozen_string_literal: true

require 'rails_helper'

# CheckSlaJob announced warnings as escalated.sla.warning, while the workflow
# subscriber listens for escalated.notification.sla_warning, so nothing ever
# heard one.
RSpec.describe Escalated::CheckSlaJob do
  let!(:ticket) do
    create(:escalated_ticket, status: :open, sla_first_response_due_at: 30.minutes.from_now, first_response_at: nil)
  end

  before do
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)
  end

  it 'announces a warning where its subscribers listen' do
    received = []
    subscriber = ActiveSupport::Notifications.subscribe('escalated.notification.sla_warning') do |*, payload|
      received << payload
    end

    described_class.perform_now

    expect(received).to include(a_hash_including(ticket: ticket, warning_type: :first_response_warning))
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it 'runs an sla.warning workflow' do
    Escalated::Services::WorkflowSubscriber.subscribe!
    workflow = create(:escalated_workflow, trigger_event: 'sla.warning', conditions: { 'all' => [] },
                                           actions: [{ 'type' => 'add_note', 'value' => 'SLA due within the hour' }])

    described_class.perform_now

    expect(Escalated::WorkflowLog.where(workflow_id: workflow.id, ticket_id: ticket.id, status: 'success'))
      .to exist
  end
end
