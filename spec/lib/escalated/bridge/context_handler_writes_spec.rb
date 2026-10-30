# frozen_string_literal: true

require 'rails_helper'

# domain-model/plugin-contract.md: ctx.replies.create, ctx.tickets.create,
# ctx.tickets.update, ctx.contacts.create and ctx.tags.create take only the
# contract's fields. Any other key is an error, never an attribute, so a
# plugin cannot name an author, a requester, an assignee, a reply's flags or
# a user's admin bit.
RSpec.describe Escalated::Bridge::ContextHandler do
  let(:handler) { described_class.new.tap { |h| h.current_plugin = 'acme' } }
  let(:agent) { create(:user, :agent, email: 'ctx-writes-agent@example.test') }
  let(:requester) { create(:user, email: 'ctx-writes-requester@example.test') }
  let(:ticket) { create(:escalated_ticket, requester: requester, subject: 'Original', priority: :low) }

  describe 'ctx.replies.create' do
    it 'writes as the acting user, or a note with is_internal' do
      handler.acting_user = agent
      reply = handler.call('ctx.replies.create', { 'data' => { 'ticket_id' => ticket.id, 'body' => 'Synced' } })
      handler.acting_user = nil
      note = handler.call('ctx.replies.create',
                          { 'data' => { 'ticket_id' => ticket.id, 'body' => 'Inner', 'is_internal' => true } })

      reply_row = Escalated::Reply.find(reply['id'])
      note_row = Escalated::Reply.find(note['id'])
      expect(reply_row).to have_attributes(ticket_id: ticket.id, is_internal: false, is_system: false,
                                           author_id: agent.id, author_type: agent.class.name)
      expect(note_row).to have_attributes(is_internal: true, is_system: false, author_id: nil)
    end

    it 'rejects fields outside the contract' do
      { 'author_id' => 1, 'author_type' => 'User', 'is_system' => true, 'is_pinned' => true,
        'is_internal_note' => true, 'id' => 999 }.each do |key, value|
        expect do
          handler.call('ctx.replies.create', { 'data' => { 'ticket_id' => ticket.id, 'body' => 'x', key => value } })
        end.to raise_error(ArgumentError, /does not accept/)
      end
      expect(Escalated::Reply.where(ticket_id: ticket.id).count).to eq(0)
    end

    it 'requires an existing ticket and a body' do
      [{ 'body' => 'x' }, { 'ticket_id' => 0, 'body' => 'x' },
       { 'ticket_id' => ticket.id, 'body' => ' ' }].each do |data|
        expect { handler.call('ctx.replies.create', { 'data' => data }) }.to raise_error(ArgumentError)
      end
    end
  end

  describe 'ctx.tickets.create' do
    it 'takes the contract fields and aliases, with the requester as a contact' do
      created = handler.call('ctx.tickets.create', { 'data' => {
                               'title' => 'From Slack', 'description' => 'Help', 'priority' => 'high',
                               'metadata' => { 'slack_ts' => '1.2' }, 'channel' => 'api',
                               'requester_email' => 'Pat@Example.com', 'requester_name' => 'Pat'
                             } })

      row = Escalated::Ticket.find(created['id'])
      expect(row).to have_attributes(subject: 'From Slack', description: 'Help', priority: 'high',
                                     requester_id: nil, assigned_to: nil)
      expect(row.metadata).to eq({ 'slack_ts' => '1.2' })
      expect(row.contact.email).to eq('pat@example.com')
    end

    it 'rejects fields outside the contract' do
      ticket
      { 'requester_id' => requester.id, 'requester_type' => 'User', 'assigned_to' => agent.id,
        'reference' => 'ESC-1', 'guest_token' => 'x', 'sla_breached' => true }.each do |key, value|
        expect do
          handler.call('ctx.tickets.create', { 'data' => { 'subject' => 'S', key => value } })
        end.to raise_error(ArgumentError, /does not accept/)
      end
      expect(Escalated::Ticket.count).to eq(1)
    end
  end

  describe 'ctx.tickets.update' do
    it 'takes the contract fields only' do
      { 'assigned_to' => agent.id, 'requester_id' => agent.id, 'channel' => 'email',
        'requester_email' => 'a@b.c', 'resolved_at' => '2026-01-01' }.each do |key, value|
        expect do
          handler.call('ctx.tickets.update', { 'id' => ticket.id, 'data' => { 'subject' => 'Changed', key => value } })
        end.to raise_error(ArgumentError, /does not accept/)
      end
      expect(ticket.reload.subject).to eq('Original')

      handler.call('ctx.tickets.update', { 'id' => ticket.id,
                                           'data' => { 'title' => 'Renamed', 'body' => 'New body',
                                                       'priority' => 'urgent' } })
      expect(ticket.reload).to have_attributes(subject: 'Renamed', description: 'New body', priority: 'urgent',
                                               assigned_to: nil)
    end
  end

  describe 'ctx.contacts.create and ctx.tags.create' do
    it 'refuse anything but their contract fields' do
      expect do
        handler.call('ctx.contacts.create', { 'data' => { 'name' => 'Eve', 'email' => 'eve@example.test',
                                                          'is_admin' => true } })
      end.to raise_error(ArgumentError, /does not accept/)
      expect do
        handler.call('ctx.tags.create', { 'data' => { 'name' => 'VIP', 'id' => 5 } })
      end.to raise_error(ArgumentError, /does not accept/)

      tag = handler.call('ctx.tags.create', { 'data' => { 'name' => 'VIP', 'color' => '#ff0000' } })
      expect(Escalated::Tag.find(tag['id'])).to have_attributes(name: 'VIP', color: '#ff0000')
    end
  end
end
