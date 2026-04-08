# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Services::ChatRoutingService do
  let(:agent1) { create(:user, :agent) }
  let(:agent2) { create(:user, :agent) }

  before do
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)
    create(:escalated_agent_profile, user: agent1, chat_status: 'online')
    create(:escalated_agent_profile, user: agent2, chat_status: 'online')
  end

  describe '.find_available_agent' do
    it 'returns an available agent' do
      agent_id = described_class.find_available_agent
      expect([agent1.id, agent2.id]).to include(agent_id)
    end

    it 'returns nil when no agents are online' do
      Escalated::AgentProfile.update_all(chat_status: 'offline')
      expect(described_class.find_available_agent).to be_nil
    end

    it 'skips agents at max capacity' do
      create(:escalated_chat_routing_rule, max_concurrent_per_agent: 1)
      ticket = create(:escalated_ticket, channel: 'chat')
      create(:escalated_chat_session, :active, ticket: ticket, agent: agent1)

      agent_id = described_class.find_available_agent
      expect(agent_id).to eq(agent2.id)
    end
  end

  describe '.evaluate_routing' do
    it 'returns routing evaluation' do
      result = described_class.evaluate_routing
      expect(result[:available]).to be(true)
      expect(result[:queue_size]).to eq(0)
      expect(result[:queue_full]).to be(false)
    end

    it 'reports unavailable when no agents online' do
      Escalated::AgentProfile.update_all(chat_status: 'offline')
      result = described_class.evaluate_routing
      expect(result[:available]).to be(false)
    end

    it 'uses routing rule settings' do
      create(:escalated_chat_routing_rule,
             offline_behavior: 'show_message',
             offline_message: 'We are offline',
             queue_message: 'Please wait')
      result = described_class.evaluate_routing
      expect(result[:offline_behavior]).to eq('show_message')
      expect(result[:offline_message]).to eq('We are offline')
      expect(result[:queue_message]).to eq('Please wait')
    end
  end

  describe '.get_queue_position' do
    it 'returns the position in queue' do
      session1 = create(:escalated_chat_session, :waiting, created_at: 5.minutes.ago)
      session2 = create(:escalated_chat_session, :waiting, created_at: 3.minutes.ago)
      session3 = create(:escalated_chat_session, :waiting, created_at: 1.minute.ago)

      expect(described_class.get_queue_position(session1)).to eq(1)
      expect(described_class.get_queue_position(session2)).to eq(2)
      expect(described_class.get_queue_position(session3)).to eq(3)
    end
  end
end
