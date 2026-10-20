# frozen_string_literal: true

require 'rails_helper'

# Webhook events Laravel's DispatchWebhook sends that this engine did not:
# unassigned (TicketService.unassign raised no event at all), department
# changes, SLA warnings, ticket updates and tag changes.
RSpec.describe Escalated::Services::WebhookDispatcher, '.events_for' do
  let(:agent) { create(:user, :agent) }
  let(:ticket) { create(:escalated_ticket, :with_assignee) }
  let(:events) { [] }

  before do
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)
    allow(Escalated::Broadcasting).to receive(:broadcast)
    allow_any_instance_of(described_class) # rubocop:disable RSpec/AnyInstance
      .to receive(:dispatch_later) { |_, name, data| events << [name, data] }
  end

  def names
    events.map(&:first)
  end

  it 'sends ticket.unassigned with the previous agent id as a string' do
    previous = ticket.assigned_to

    Escalated::Services::TicketService.unassign(ticket, actor: agent)

    expect(names).to include('ticket.unassigned')
    data = events.find { |name, _| name == 'ticket.unassigned' }.last
    expect(data['previous_agent_id']).to eq(previous.to_s)
  end

  it 'sends nothing for unassigning a ticket that had no agent' do
    unassigned = create(:escalated_ticket)

    Escalated::Services::TicketService.unassign(unassigned, actor: agent)

    expect(names).not_to include('ticket.unassigned')
  end

  it 'sends ticket.department_changed' do
    Escalated::Services::TicketService.change_department(ticket, create(:escalated_department), actor: agent)

    expect(names).to include('ticket.department_changed')
  end

  it 'sends ticket.updated' do
    Escalated::Services::TicketService.update(ticket, { subject: 'New subject' }, actor: agent)

    expect(names).to include('ticket.updated')
  end

  it 'sends ticket.tag_added and ticket.tag_removed once per tag that changed' do
    tag = create(:escalated_tag, name: 'vip')

    Escalated::Services::TicketService.add_tags(ticket, [tag.id], actor: agent)
    Escalated::Services::TicketService.add_tags(ticket, [tag.id], actor: agent)
    Escalated::Services::TicketService.remove_tags(ticket, [tag.id], actor: agent)

    expect(names.count('ticket.tag_added')).to eq(1)
    expect(names.count('ticket.tag_removed')).to eq(1)
    expect(events.find { |name, _| name == 'ticket.tag_added' }.last['tag_name']).to eq('vip')
  end

  it 'sends sla.warning' do
    Escalated::Services::NotificationService.dispatch(:sla_warning, ticket: ticket, warning_type: 'first_response')

    expect(names).to include('sla.warning')
  end

  it 'offers every event it sends' do
    expect(Escalated::Services::WebhookDispatcher::AVAILABLE_EVENTS)
      .to include('ticket.unassigned', 'ticket.department_changed', 'ticket.updated', 'ticket.tag_added',
                  'ticket.tag_removed', 'sla.warning')
  end
end
