# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Services::TicketService do
  let(:agent) { create(:user, :agent) }

  before do
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)
  end

  describe '.snooze_ticket' do
    let(:ticket) { create(:escalated_ticket, status: :in_progress) }
    let(:snooze_until) { 2.hours.from_now }

    it 'sets snoozed_until on the ticket' do
      described_class.snooze_ticket(ticket, snooze_until, actor: agent)
      ticket.reload
      expect(ticket.snoozed_until).to be_within(1.second).of(snooze_until)
    end

    it 'records the snoozed_by user' do
      described_class.snooze_ticket(ticket, snooze_until, actor: agent)
      ticket.reload
      expect(ticket.snoozed_by).to eq(agent.id)
    end

    it 'saves the status before snooze' do
      described_class.snooze_ticket(ticket, snooze_until, actor: agent)
      ticket.reload
      expect(ticket.status_before_snooze).to eq(Escalated::Ticket.statuses['in_progress'])
    end

    it 'marks the ticket as snoozed' do
      described_class.snooze_ticket(ticket, snooze_until, actor: agent)
      ticket.reload
      expect(ticket.snoozed?).to be true
    end
  end

  describe '.unsnooze_ticket' do
    let(:ticket) do
      create(:escalated_ticket,
             status: :in_progress,
             snoozed_until: 1.hour.from_now,
             snoozed_by: agent.id,
             status_before_snooze: Escalated::Ticket.statuses['waiting_on_customer'])
    end

    it 'clears the snoozed_until field' do
      described_class.unsnooze_ticket(ticket)
      ticket.reload
      expect(ticket.snoozed_until).to be_nil
    end

    it 'clears the snoozed_by field' do
      described_class.unsnooze_ticket(ticket)
      ticket.reload
      expect(ticket.snoozed_by).to be_nil
    end

    it 'restores the previous status' do
      described_class.unsnooze_ticket(ticket)
      ticket.reload
      expect(ticket.status).to eq('waiting_on_customer')
    end

    it 'clears status_before_snooze' do
      described_class.unsnooze_ticket(ticket)
      ticket.reload
      expect(ticket.status_before_snooze).to be_nil
    end

    it 'marks the ticket as not snoozed' do
      described_class.unsnooze_ticket(ticket)
      ticket.reload
      expect(ticket.snoozed?).to be false
    end
  end
end

RSpec.describe Escalated::Ticket do # snooze scopes
  before do
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)
  end

  let!(:snoozed_ticket) { create(:escalated_ticket, snoozed_until: 2.hours.from_now) }
  let!(:expired_snooze_ticket) { create(:escalated_ticket, snoozed_until: 1.hour.ago) }
  let!(:normal_ticket) { create(:escalated_ticket, snoozed_until: nil) }

  describe '.snoozed' do
    it 'returns only actively snoozed tickets' do
      result = described_class.snoozed
      expect(result).to include(snoozed_ticket)
      expect(result).not_to include(expired_snooze_ticket, normal_ticket)
    end
  end

  describe '.not_snoozed' do
    it 'returns tickets that are not snoozed' do
      result = described_class.not_snoozed
      expect(result).to include(expired_snooze_ticket, normal_ticket)
      expect(result).not_to include(snoozed_ticket)
    end
  end

  describe '.snooze_expired' do
    it 'returns tickets whose snooze has expired' do
      result = described_class.snooze_expired
      expect(result).to include(expired_snooze_ticket)
      expect(result).not_to include(snoozed_ticket, normal_ticket)
    end
  end

  describe '#snoozed?' do
    it 'returns true for snoozed ticket' do
      expect(snoozed_ticket.snoozed?).to be true
    end

    it 'returns false for expired snooze ticket' do
      expect(expired_snooze_ticket.snoozed?).to be false
    end

    it 'returns false for normal ticket' do
      expect(normal_ticket.snoozed?).to be false
    end
  end
end
