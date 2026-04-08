# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Broadcasting do
  let(:user) { create(:user) }
  let(:agent) { create(:user, :agent) }
  let(:ticket) { create(:escalated_ticket, requester: user) }

  before do
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)
  end

  describe '.enabled?' do
    it 'defaults to false' do
      expect(described_class.enabled?).to be false
    end

    it 'returns true when broadcasting_enabled setting is set' do
      Escalated::EscalatedSetting.set('broadcasting_enabled', '1')
      expect(described_class.enabled?).to be true
    end

    it 'returns false when broadcasting_enabled is 0' do
      Escalated::EscalatedSetting.set('broadcasting_enabled', '0')
      expect(described_class.enabled?).to be false
    end
  end

  describe '.ticket_channel' do
    it 'returns channel name for ticket' do
      expect(described_class.ticket_channel(ticket)).to eq("escalated_ticket_#{ticket.id}")
    end

    it 'accepts a plain ID' do
      expect(described_class.ticket_channel(42)).to eq('escalated_ticket_42')
    end
  end

  describe '.agent_channel' do
    it 'returns global agent channel when no ID given' do
      expect(described_class.agent_channel).to eq('escalated_agents')
    end

    it 'returns agent-specific channel when ID given' do
      expect(described_class.agent_channel(5)).to eq('escalated_agent_5')
    end
  end

  context 'when broadcasting is disabled' do
    before do
      Escalated::EscalatedSetting.set('broadcasting_enabled', '0')
    end

    it 'does not call ActionCable.server.broadcast for ticket_created' do
      expect(ActionCable.server).not_to receive(:broadcast)
      described_class.ticket_created(ticket)
    end

    it 'does not call ActionCable.server.broadcast for ticket_updated' do
      expect(ActionCable.server).not_to receive(:broadcast)
      described_class.ticket_updated(ticket)
    end

    it 'does not call ActionCable.server.broadcast for reply_created' do
      reply = create(:escalated_reply, ticket: ticket, author: agent)
      expect(ActionCable.server).not_to receive(:broadcast)
      described_class.reply_created(ticket, reply)
    end
  end

  context 'when broadcasting is enabled' do
    before do
      Escalated::EscalatedSetting.set('broadcasting_enabled', '1')
    end

    describe '.ticket_created' do
      it 'broadcasts to agent channel' do
        expect(ActionCable.server).to receive(:broadcast).with(
          'escalated_agents',
          hash_including(event: 'ticket_created')
        )
        described_class.ticket_created(ticket)
      end
    end

    describe '.ticket_updated' do
      it 'broadcasts to ticket channel and agent channel' do
        expect(ActionCable.server).to receive(:broadcast).with(
          "escalated_ticket_#{ticket.id}",
          hash_including(event: 'ticket_updated')
        )
        expect(ActionCable.server).to receive(:broadcast).with(
          'escalated_agents',
          hash_including(event: 'ticket_updated')
        )
        described_class.ticket_updated(ticket)
      end
    end

    describe '.ticket_status_changed' do
      it 'broadcasts with old and new status' do
        expect(ActionCable.server).to receive(:broadcast).with(
          "escalated_ticket_#{ticket.id}",
          hash_including(event: 'ticket_status_changed', data: hash_including(old_status: 'open', new_status: 'closed'))
        )
        expect(ActionCable.server).to receive(:broadcast).with(
          'escalated_agents',
          hash_including(event: 'ticket_status_changed')
        )
        described_class.ticket_status_changed(ticket, :open, :closed)
      end
    end

    describe '.reply_created' do
      let(:reply) { create(:escalated_reply, ticket: ticket, author: agent) }

      it 'broadcasts to ticket channel' do
        expect(ActionCable.server).to receive(:broadcast).with(
          "escalated_ticket_#{ticket.id}",
          hash_including(event: 'reply_created')
        )
        described_class.reply_created(ticket, reply)
      end
    end

    describe '.ticket_assigned' do
      it 'broadcasts to ticket channel and agent-specific channel' do
        expect(ActionCable.server).to receive(:broadcast).with(
          "escalated_ticket_#{ticket.id}",
          hash_including(event: 'ticket_assigned')
        )
        expect(ActionCable.server).to receive(:broadcast).with(
          "escalated_agent_#{agent.id}",
          hash_including(event: 'ticket_assigned')
        )
        described_class.ticket_assigned(ticket, agent)
      end
    end

    describe '.ticket_escalated' do
      it 'broadcasts to ticket channel and agent channel' do
        expect(ActionCable.server).to receive(:broadcast).with(
          "escalated_ticket_#{ticket.id}",
          hash_including(event: 'ticket_escalated')
        )
        expect(ActionCable.server).to receive(:broadcast).with(
          'escalated_agents',
          hash_including(event: 'ticket_escalated')
        )
        described_class.ticket_escalated(ticket)
      end
    end
  end

  describe 'error handling' do
    before do
      Escalated::EscalatedSetting.set('broadcasting_enabled', '1')
    end

    it 'catches and logs errors without raising' do
      allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError, 'Connection refused')
      expect(Rails.logger).to receive(:warn).with(/Failed to broadcast/)
      expect { described_class.ticket_created(ticket) }.not_to raise_error
    end
  end
end
