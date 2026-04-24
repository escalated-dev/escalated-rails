# frozen_string_literal: true

require 'rails_helper'
require 'escalated/mail/inbound_message'
require 'escalated/mail/message_id_util'

RSpec.describe Escalated::Services::InboundEmailService do
  let(:service) { described_class.new }
  let(:ticket) { create(:escalated_ticket) }
  let(:message_class) { Escalated::Mail::InboundMessage }

  # Helper for building inbound messages with minimal ceremony.
  def inbound(**overrides)
    defaults = {
      from_email: 'customer@example.com',
      from_name: 'Customer',
      to_email: 'support@example.com',
      subject: 'test',
      body_text: 'hello',
      message_id: '<inbound-1@mail.client>'
    }
    message_class.new(**defaults, **overrides)
  end

  describe '#find_existing_ticket' do
    context 'when In-Reply-To carries a canonical Message-ID' do
      it 'parses the ticket id out of the header via MessageIdUtil' do
        # No InboundEmail row — this is the cold-start path.
        message = inbound(in_reply_to: "<ticket-#{ticket.id}@support.example.com>")

        found = described_class.send(:find_existing_ticket, message)
        expect(found).to eq(ticket)
      end
    end

    context 'when References carries a canonical Message-ID' do
      it 'parses the ticket id out of any element' do
        message = inbound(
          references: ['<unrelated@mail.com>', "<ticket-#{ticket.id}@support.example.com>"]
        )

        found = described_class.send(:find_existing_ticket, message)
        expect(found).to eq(ticket)
      end
    end

    context 'when to_email carries a signed Reply-To and inbound_secret is configured' do
      before do
        allow(Escalated.configuration).to receive_messages(
          email_domain: 'support.example.com',
          email_inbound_secret: 'test-secret'
        )
      end

      it 'verifies the HMAC and returns the ticket' do
        to = Escalated::Mail::MessageIdUtil.build_reply_to(ticket.id, 'test-secret', 'support.example.com')
        message = inbound(to_email: to)

        found = described_class.send(:find_existing_ticket, message)
        expect(found).to eq(ticket)
      end

      it 'rejects a signature signed with the wrong secret' do
        forged = Escalated::Mail::MessageIdUtil.build_reply_to(ticket.id, 'wrong-secret', 'support.example.com')
        message = inbound(to_email: forged)

        found = described_class.send(:find_existing_ticket, message)
        expect(found).to be_nil
      end
    end

    context 'when inbound_secret is blank' do
      before do
        allow(Escalated.configuration).to receive(:email_inbound_secret).and_return('')
      end

      it 'ignores signed-Reply-To addresses in to_email' do
        # Even a correctly-signed address is ignored when signing is off.
        to = Escalated::Mail::MessageIdUtil.build_reply_to(ticket.id, 'test-secret', 'support.example.com')
        message = inbound(to_email: to)

        found = described_class.send(:find_existing_ticket, message)
        expect(found).to be_nil
      end
    end

    context 'when the subject carries a ticket reference tag' do
      # InboundMessage#ticket_reference matches Rails's
      # Escalated::Ticket#generate_reference format: ESC-YYMM-SHORTCODE.
      let(:ticket) { create(:escalated_ticket, reference: 'ESC-2604-ABC123') }

      it 'matches by reference' do
        ticket # force lazy-let creation before the service runs
        message = inbound(subject: 'RE: [ESC-2604-ABC123] foo')

        found = described_class.send(:find_existing_ticket, message)
        expect(found).to eq(ticket)
      end
    end

    context 'with nothing to match against' do
      it 'returns nil' do
        message = inbound(subject: 'New issue')

        found = described_class.send(:find_existing_ticket, message)
        expect(found).to be_nil
      end
    end
  end
end
