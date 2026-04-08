# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Services::ChatAvailabilityService do
  let(:agent) { create(:user, :agent) }

  describe '.available?' do
    it 'returns true when agents are online' do
      create(:escalated_agent_profile, user: agent, chat_status: 'online')
      expect(described_class.available?).to be(true)
    end

    it 'returns false when no agents are online' do
      create(:escalated_agent_profile, user: agent, chat_status: 'offline')
      expect(described_class.available?).to be(false)
    end

    it 'filters by department' do
      dept = create(:escalated_department)
      dept.agents << agent
      create(:escalated_agent_profile, user: agent, chat_status: 'online')

      expect(described_class.available?(department_id: dept.id)).to be(true)
    end

    it 'returns false when department has no online agents' do
      dept = create(:escalated_department)
      other_agent = create(:user, :agent)
      create(:escalated_agent_profile, user: other_agent, chat_status: 'online')

      expect(described_class.available?(department_id: dept.id)).to be(false)
    end
  end

  describe '.online_agents' do
    it 'returns online agent profiles' do
      profile = create(:escalated_agent_profile, user: agent, chat_status: 'online')
      offline_agent = create(:user, :agent)
      create(:escalated_agent_profile, user: offline_agent, chat_status: 'offline')

      result = described_class.online_agents
      expect(result).to include(profile)
      expect(result.count).to eq(1)
    end
  end

  describe '.agent_chat_count' do
    it 'returns the number of active chats for an agent' do
      ticket1 = create(:escalated_ticket, channel: 'chat')
      ticket2 = create(:escalated_ticket, channel: 'chat')
      create(:escalated_chat_session, :active, ticket: ticket1, agent: agent)
      create(:escalated_chat_session, :active, ticket: ticket2, agent: agent)
      create(:escalated_chat_session, :ended, agent: agent)

      expect(described_class.agent_chat_count(agent.id)).to eq(2)
    end
  end

  describe '.agent_available?' do
    before do
      create(:escalated_agent_profile, user: agent, chat_status: 'online')
    end

    it 'returns true when agent is below capacity' do
      expect(described_class.agent_available?(agent.id, max_concurrent: 5)).to be(true)
    end

    it 'returns false when agent is at capacity' do
      5.times do
        ticket = create(:escalated_ticket, channel: 'chat')
        create(:escalated_chat_session, :active, ticket: ticket, agent: agent)
      end

      expect(described_class.agent_available?(agent.id, max_concurrent: 5)).to be(false)
    end

    it 'returns false when agent is offline' do
      Escalated::AgentProfile.find_by(user_id: agent.id).update!(chat_status: 'offline')
      expect(described_class.agent_available?(agent.id)).to be(false)
    end
  end
end
