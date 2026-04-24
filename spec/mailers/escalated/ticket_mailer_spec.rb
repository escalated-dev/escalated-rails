# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::TicketMailer do
  let(:user) { create(:user) }
  let(:agent) { create(:user, :agent) }
  let(:ticket) { create(:escalated_ticket, requester: user, assigned_to: agent.id) }

  before do
    allow(Escalated.configuration).to receive_messages(notification_channels: [:email], webhook_url: nil)
  end

  describe '#new_ticket' do
    let(:mail) { described_class.new_ticket(ticket) }

    it 'sets a Message-ID header' do
      expect(mail['Message-ID'].to_s).to match(/ticket-#{ticket.id}@/)
    end

    it 'sends to the requester' do
      expect(mail.to).to include(user.email)
    end

    it 'loads branding variables' do
      Escalated::EscalatedSetting.set('email_logo_url', 'https://example.com/logo.png')
      Escalated::EscalatedSetting.set('email_accent_color', '#FF0000')
      Escalated::EscalatedSetting.set('email_footer_text', 'Powered by Escalated')

      # Mail should build without error
      expect(mail.subject).to be_present
    end
  end

  describe '#reply_received' do
    let(:reply) { create(:escalated_reply, ticket: ticket, author: agent) }
    let(:mail) { described_class.reply_received(ticket, reply) }

    it 'sets In-Reply-To header referencing the ticket' do
      expect(mail['In-Reply-To'].to_s).to match(/ticket-#{ticket.id}@/)
    end

    it 'sets References header referencing the ticket' do
      expect(mail['References'].to_s).to match(/ticket-#{ticket.id}@/)
    end

    it 'sends to the requester when agent replies' do
      expect(mail.to).to include(user.email)
    end
  end

  describe '#ticket_assigned' do
    before { ticket.update!(assigned_to: agent.id) }

    let(:mail) { described_class.ticket_assigned(ticket) }

    it 'sets threading headers' do
      expect(mail['In-Reply-To'].to_s).to match(/ticket-#{ticket.id}@/)
      expect(mail['References'].to_s).to match(/ticket-#{ticket.id}@/)
    end

    it 'sends to the assignee' do
      expect(mail.to).to include(agent.email)
    end
  end

  describe '#status_changed' do
    let(:mail) { described_class.status_changed(ticket) }

    it 'sets threading headers' do
      expect(mail['In-Reply-To'].to_s).to match(/ticket-#{ticket.id}@/)
    end
  end

  describe '#ticket_resolved' do
    let(:mail) { described_class.ticket_resolved(ticket) }

    it 'sets threading headers' do
      expect(mail['In-Reply-To'].to_s).to match(/ticket-#{ticket.id}@/)
      expect(mail['References'].to_s).to match(/ticket-#{ticket.id}@/)
    end
  end

  describe 'RFC 5322 threading + signed Reply-To (MessageIdUtil wire-up)' do
    before do
      allow(Escalated.configuration).to receive(:email_domain).and_return('support.example.com')
    end

    it 'uses the configured email_domain in the Message-ID' do
      mail = described_class.new_ticket(ticket)
      expect(mail['Message-ID'].to_s).to include('@support.example.com')
    end

    it 'builds the reply Message-ID with the reply id' do
      reply = create(:escalated_reply, ticket: ticket, author: agent)
      mail = described_class.reply_received(ticket, reply)
      expect(mail['Message-ID'].to_s).to match(/ticket-#{ticket.id}-reply-#{reply.id}@/)
    end

    context 'when email_inbound_secret is configured' do
      before do
        allow(Escalated.configuration).to receive(:email_inbound_secret).and_return('test-secret')
      end

      it 'sets a signed Reply-To on the initial ticket notification' do
        mail = described_class.new_ticket(ticket)
        expect(mail['Reply-To'].to_s).to match(/\Areply\+#{ticket.id}\.[a-f0-9]{8}@support\.example\.com\z/)
      end

      it 'sets a signed Reply-To on reply notifications' do
        reply = create(:escalated_reply, ticket: ticket, author: agent)
        mail = described_class.reply_received(ticket, reply)
        expect(mail['Reply-To'].to_s).to match(/\Areply\+#{ticket.id}\.[a-f0-9]{8}@support\.example\.com\z/)
      end

      it 'sets a signed Reply-To on status-changed notifications' do
        mail = described_class.status_changed(ticket)
        expect(mail['Reply-To'].to_s).to match(/\Areply\+#{ticket.id}\.[a-f0-9]{8}@support\.example\.com\z/)
      end
    end

    context 'when email_inbound_secret is blank' do
      before do
        allow(Escalated.configuration).to receive(:email_inbound_secret).and_return('')
      end

      it 'omits the Reply-To header entirely' do
        mail = described_class.new_ticket(ticket)
        expect(mail['Reply-To']).to be_nil
      end
    end
  end

  describe 'branding settings' do
    it 'uses default accent color when not configured' do
      mail = described_class.new_ticket(ticket)
      # Should not raise error
      expect(mail.subject).to be_present
    end

    it 'reads configured branding from settings' do
      Escalated::EscalatedSetting.set('email_logo_url', 'https://example.com/logo.png')
      Escalated::EscalatedSetting.set('email_accent_color', '#FF5733')
      Escalated::EscalatedSetting.set('email_footer_text', 'Custom footer text')

      mail = described_class.new_ticket(ticket)
      expect(mail.subject).to be_present
    end
  end
end
