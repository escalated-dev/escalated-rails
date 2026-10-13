# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Services::InboundEmailService do
  let(:secret) { 'test-secret' }
  let(:domain) { 'support.example.com' }
  let(:inbound_secret) { nil }
  let(:requester) { create(:user, email: 'owner@example.com') }

  before do
    allow(Escalated.configuration).to receive_messages(
      inbound_email_enabled: true,
      notification_channels: [],
      webhook_url: nil,
      email_inbound_secret: inbound_secret,
      email_domain: domain
    )
  end

  def message(**attrs)
    Escalated::Mail::InboundMessage.new(
      from_email: 'owner@example.com',
      from_name: 'Owner',
      to_email: "support@#{domain}",
      subject: 'Question',
      body_text: 'Hello',
      message_id: "<#{SecureRandom.hex(8)}@mail.example.net>",
      **attrs
    )
  end

  def process(msg)
    described_class.process(msg, adapter_name: 'mailgun')
  end

  def signed_reply_to(ticket)
    Escalated::Mail::MessageIdUtil.build_reply_to(ticket.id, secret, domain)
  end

  describe 'without an inbound secret' do
    it 'accepts a reply from the requester matched by subject reference' do
      ticket = create(:escalated_ticket, requester: requester)

      inbound = process(message(from_email: 'Owner@Example.com', subject: "RE: [#{ticket.reference}] Question"))

      expect(inbound.ticket_id).to eq(ticket.id)
      expect(inbound.reply.author).to eq(requester)
    end

    it 'threads a guest reply through the canonical In-Reply-To Message-ID' do
      ticket = create(:escalated_ticket, requester: nil, guest_email: 'guest@example.com',
                                         guest_token: SecureRandom.hex(16))

      inbound = process(message(from_email: 'guest@example.com',
                                in_reply_to: "<ticket-#{ticket.id}@#{domain}>"))

      expect(inbound.ticket_id).to eq(ticket.id)
      expect(inbound.reply).to be_present
      expect(inbound.reply.author).to be_nil
    end

    it 'reopens a closed guest ticket when the guest replies' do
      ticket = create(:escalated_ticket, :closed, requester: nil, guest_email: 'guest@example.com',
                                                  guest_token: SecureRandom.hex(16))

      inbound = process(message(from_email: 'GUEST@example.com', subject: "RE: [#{ticket.reference}] Closed"))

      expect(inbound.ticket_id).to eq(ticket.id)
      expect(ticket.reload).to be_reopened
    end

    it 'opens a new ticket when a stranger quotes a ticket reference in the subject' do
      ticket = create(:escalated_ticket, requester: requester)

      inbound = process(message(from_email: 'stranger@example.net', subject: "RE: [#{ticket.reference}] Your order"))

      expect(inbound.status).to eq('processed')
      expect(inbound.ticket_id).not_to eq(ticket.id)
      expect(inbound.reply_id).to be_nil
      expect(ticket.replies.count).to eq(0)
      expect(Escalated::Ticket.find(inbound.ticket_id).guest_email).to eq('stranger@example.net')
    end

    it 'does not reopen a closed ticket for a stranger who threads onto it' do
      ticket = create(:escalated_ticket, :closed, requester: requester)

      inbound = process(message(from_email: 'stranger@example.net',
                                subject: "RE: [#{ticket.reference}] Closed",
                                in_reply_to: "<ticket-#{ticket.id}@#{domain}>"))

      expect(inbound.ticket_id).not_to eq(ticket.id)
      expect(ticket.reload).to be_closed
      expect(ticket.replies.count).to eq(0)
    end

    it 'reopens a closed ticket when the requester replies' do
      ticket = create(:escalated_ticket, :closed, requester: requester)

      inbound = process(message(subject: "RE: [#{ticket.reference}] Closed"))

      expect(inbound.ticket_id).to eq(ticket.id)
      expect(ticket.reload).to be_reopened
    end
  end

  describe 'with an inbound secret' do
    let(:inbound_secret) { secret }

    it 'never posts as an agent because the From header names one' do
      agent = create(:user, :agent, email: 'agent@example.com')
      ticket = create(:escalated_ticket, requester: requester)

      inbound = process(message(from_email: 'agent@example.com',
                                to_email: signed_reply_to(ticket),
                                subject: "RE: [#{ticket.reference}] Update",
                                in_reply_to: "<ticket-#{ticket.id}@#{domain}>"))

      expect(inbound.ticket_id).not_to eq(ticket.id)
      expect(ticket.replies.count).to eq(0)
      expect(Escalated::Reply.where(author: agent).count).to eq(0)
    end

    it 'requires the signed Reply-To address to link mail to a ticket' do
      ticket = create(:escalated_ticket, requester: requester)

      inbound = process(message(subject: "RE: [#{ticket.reference}] Question",
                                in_reply_to: "<ticket-#{ticket.id}@#{domain}>"))

      expect(inbound.ticket_id).not_to eq(ticket.id)
      expect(ticket.replies.count).to eq(0)
    end

    it 'rejects a forged Reply-To signature' do
      ticket = create(:escalated_ticket, requester: requester)

      inbound = process(message(to_email: "reply+#{ticket.id}.deadbeef@#{domain}"))

      expect(inbound.ticket_id).not_to eq(ticket.id)
      expect(ticket.replies.count).to eq(0)
    end

    it 'accepts a signed reply from the requester and reopens the ticket as the requester' do
      ticket = create(:escalated_ticket, :resolved, requester: requester)

      inbound = process(message(from_email: 'Owner@Example.com', to_email: signed_reply_to(ticket)))

      expect(inbound.ticket_id).to eq(ticket.id)
      expect(inbound.reply.author).to eq(requester)
      expect(ticket.reload).to be_reopened
    end
  end
end
