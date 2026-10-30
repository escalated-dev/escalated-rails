# frozen_string_literal: true

require 'rails_helper'

# domain-model/plugin-contract.md: ctx.tickets.create/update and
# ctx.replies.create go through the ticket service, so a plugin's ticket or
# reply gets the same activity log, SLA, canonical events, workflows and
# webhooks as one written over the HTTP API. A plugin's own write does not
# re-deliver the event it is handling back to plugins.
RSpec.describe Escalated::Bridge::ContextHandler do
  let(:handler) { described_class.new.tap { |h| h.current_plugin = 'acme' } }
  let(:agent) { create(:user, :agent, email: 'ctx-service-agent@example.test') }
  let(:requester) { create(:user, email: 'ctx-service-requester@example.test') }
  let(:ticket) { create(:escalated_ticket, requester: requester, status: :open, priority: :low) }
  let(:seen) { [] }

  before do
    Escalated.reset_plugins!
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)
    allow(Escalated::Broadcasting).to receive(:broadcast)
  end

  after { Escalated.reset_plugins! }

  def listen(*names)
    names.each do |name|
      Escalated.hooks.add_action(name) { |payload| seen << [name, payload] }
    end
  end

  def actions(record)
    Escalated::TicketActivity.where(ticket_id: record.id).order(:id).pluck(:action)
  end

  describe 'ctx.tickets.create' do
    it 'logs the creation, attaches the default SLA and announces ticket.created' do
      allow(Escalated.configuration).to receive(:sla_enabled?).and_return(true)
      create(:escalated_sla_policy, is_default: true, is_active: true)
      listen('ticket.created')
      handler.acting_user = agent

      created = handler.call('ctx.tickets.create', { 'data' => { 'subject' => 'From a plugin' } })

      row = Escalated::Ticket.find(created['id'])
      expect(row.sla_policy_id).not_to be_nil
      expect(row.priority).to eq(Escalated.configuration.default_priority.to_s)
      expect(actions(row)).to eq(['ticket_created'])
      expect(seen.map(&:first)).to eq(['ticket.created'])
      expect(seen.first.last['id']).to eq(row.id)
    end

    it 'reaches a requested status as a logged, announced status change' do
      listen('ticket.status_changed')

      data = { 'subject' => 'Waiting', 'status' => 'waiting_on_customer' }
      created = handler.call('ctx.tickets.create', { 'data' => data })

      row = Escalated::Ticket.find(created['id'])
      expect(row.status).to eq('waiting_on_customer')
      expect(actions(row)).to eq(%w[ticket_created status_changed])
      expect(seen.map(&:first)).to eq(['ticket.status_changed'])
    end
  end

  describe 'ctx.tickets.update' do
    it 'changes status, priority and department through the service, logged and announced' do
      department = create(:escalated_department)
      listen('ticket.status_changed', 'ticket.priority_changed', 'ticket.department_changed')
      handler.acting_user = agent

      handler.call('ctx.tickets.update', { 'id' => ticket.id, 'data' => {
                     'status' => 'in_progress', 'priority' => 'urgent', 'department_id' => department.id
                   } })

      expect(ticket.reload).to have_attributes(status: 'in_progress', priority: 'urgent',
                                               department_id: department.id)
      expect(actions(ticket)).to include('status_changed', 'priority_changed', 'department_changed')
      expect(Escalated::TicketActivity.where(ticket_id: ticket.id).pluck(:causer_id).uniq).to eq([agent.id])
      expect(seen.map(&:first)).to contain_exactly('ticket.status_changed', 'ticket.priority_changed',
                                                   'ticket.department_changed')
    end

    it 'logs and announces a subject change as ticket.updated' do
      listen('ticket.updated')

      handler.call('ctx.tickets.update', { 'id' => ticket.id, 'data' => { 'title' => 'Renamed' } })

      expect(ticket.reload.subject).to eq('Renamed')
      expect(actions(ticket)).to eq(['ticket_updated'])
      expect(seen.map(&:first)).to eq(['ticket.updated'])
    end
  end

  describe 'ctx.replies.create' do
    it 'logs replies and notes by the acting user and announces them' do
      listen('reply.created', 'note.created')
      handler.acting_user = agent

      handler.call('ctx.replies.create', { 'data' => { 'ticket_id' => ticket.id, 'body' => 'Synced' } })
      note = { 'ticket_id' => ticket.id, 'body' => 'Note', 'is_internal' => true }
      handler.call('ctx.replies.create', { 'data' => note })

      expect(actions(ticket)).to include('reply_added', 'internal_note_added')
      expect(seen.map(&:first)).to eq(%w[reply.created note.created])
      expect(ticket.reload.first_response_at).not_to be_nil
    end

    it 'logs a reply with no acting user with no causer' do
      handler.call('ctx.replies.create', { 'data' => { 'ticket_id' => ticket.id, 'body' => 'From cron' } })

      activity = Escalated::TicketActivity.find_by!(ticket_id: ticket.id, action: 'reply_added')
      expect(activity.causer_id).to be_nil
    end
  end

  describe 'loop guard' do
    it 'does not hand a plugin the event its own write raised while it handles that event' do
      calls = 0
      Escalated.hooks.add_action('ticket.created') do |_payload|
        calls += 1
        next if calls > 5

        described_class.new.tap { |h| h.current_plugin = 'acme' }
                       .call('ctx.tickets.create', { 'data' => { 'subject' => 'Follow-up' } })
      end

      handler.call('ctx.tickets.create', { 'data' => { 'subject' => 'First' } })

      expect(calls).to eq(1)
      expect(Escalated::Ticket.count).to eq(2)
    end

    it 'still delivers other events a plugin write raises while it handles one' do
      Escalated.hooks.add_action('ticket.created') do |payload|
        described_class.new.tap { |h| h.current_plugin = 'acme' }
                       .call('ctx.replies.create', { 'data' => { 'ticket_id' => payload['id'], 'body' => 'Thanks' } })
      end
      listen('reply.created')

      handler.call('ctx.tickets.create', { 'data' => { 'subject' => 'First' } })

      expect(seen.map(&:first)).to eq(['reply.created'])
    end
  end
end
