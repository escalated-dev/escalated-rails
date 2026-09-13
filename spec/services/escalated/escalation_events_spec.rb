# frozen_string_literal: true

require 'rails_helper'

# An escalation rule changes a ticket, and the rest of the engine has to hear
# about it: workflows, webhooks, followers and plugin hooks all listen on the
# same dispatch path TicketService uses. The rule's field changes were written
# straight to the row, and ticket_escalated went out only when the rule also
# asked for an email.
RSpec.describe Escalated::Services::EscalationService, '.evaluate_ticket' do
  let(:agent) { create(:user, :agent) }
  let(:ticket) do
    create(:escalated_ticket, status: :open, priority: :low, sla_first_response_due_at: 2.hours.ago,
                              first_response_at: nil)
  end

  before do
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)
    Escalated::Services::WorkflowSubscriber.subscribe!
  end

  def rule(actions)
    create(:escalated_escalation_rule, conditions: { 'status' => ['open'], 'sla_breached' => true }, actions: actions)
  end

  def workflow_on(trigger)
    create(:escalated_workflow, trigger_event: trigger, conditions: { 'all' => [] },
                                actions: [{ 'type' => 'add_note', 'value' => "Heard #{trigger}" }])
  end

  def ran?(workflow)
    Escalated::WorkflowLog.exists?(workflow_id: workflow.id, ticket_id: ticket.id, status: 'success')
  end

  it 'runs a ticket.escalated workflow for a rule that sends no notification' do
    rule('change_priority' => 'urgent')
    workflow = workflow_on('ticket.escalated')

    described_class.evaluate_ticket(ticket)

    expect(ran?(workflow)).to be(true)
  end

  it 'runs a ticket.priority_changed workflow for the priority a rule sets' do
    rule('change_priority' => 'urgent')
    workflow = workflow_on('ticket.priority_changed')

    described_class.evaluate_ticket(ticket)

    expect(ticket.reload.priority).to eq('urgent')
    expect(ran?(workflow)).to be(true)
  end

  it 'dispatches each field a rule changes' do
    department = create(:escalated_department)
    rule('change_status' => 'escalated', 'assign_to_agent_id' => agent.id, 'assign_to_department_id' => department.id)
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(/\Aescalated\.notification\./) do |name, *|
      events << name.delete_prefix('escalated.notification.')
    end

    described_class.evaluate_ticket(ticket)

    expect(events).to include('status_changed', 'ticket_assigned', 'department_changed', 'ticket_escalated')
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it 'fires the plugin hook for a priority a rule sets' do
    rule('change_priority' => 'urgent')
    calls = []
    callback = ->(*args) { calls << args }
    Escalated.hooks.add_action('ticket_priority_changed', callback)

    described_class.evaluate_ticket(ticket)

    expect(calls).to eq([[ticket, 'low', 'urgent', nil]])
  ensure
    Escalated.hooks.remove_action('ticket_priority_changed', callback)
  end
end
