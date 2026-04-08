# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Escalated::Admin::ChatController' do
  let(:agent) { create(:user, :agent) }

  before do
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)
    allow(Escalated::Broadcasting).to receive(:broadcast)
    create(:escalated_agent_profile, user: agent, chat_status: 'online')
  end

  describe 'chat queue management' do
    it 'lists waiting sessions' do
      session1 = create(:escalated_chat_session, :waiting)
      session2 = create(:escalated_chat_session, :waiting)
      create(:escalated_chat_session, :active)

      waiting = Escalated::ChatSession.waiting
      expect(waiting).to include(session1, session2)
      expect(waiting.count).to eq(2)
    end

    it 'lists active sessions' do
      create(:escalated_chat_session, :waiting)
      active_session = create(:escalated_chat_session, :active, agent: agent)

      active = Escalated::ChatSession.active
      expect(active).to include(active_session)
      expect(active.count).to eq(1)
    end
  end

  describe 'accepting a chat' do
    let(:session) { create(:escalated_chat_session, :waiting) }

    it 'assigns the agent to the waiting session' do
      Escalated::Services::ChatSessionService.assign_agent(session, agent.id)
      session.reload

      expect(session.agent_id).to eq(agent.id)
      expect(session.status).to eq('active')
      expect(session.started_at).to be_present
    end

    it 'sets ticket to in_progress' do
      Escalated::Services::ChatSessionService.assign_agent(session, agent.id)
      expect(session.ticket.reload.status).to eq('in_progress')
    end
  end

  describe 'ending a chat' do
    it 'marks session as ended' do
      session = create(:escalated_chat_session, :ended, agent: agent)

      expect(session.status).to eq('ended')
      expect(session.ended_at).to be_present
    end
  end

  describe 'transferring a chat' do
    let(:new_agent) { create(:user, :agent) }
    let(:session) { create(:escalated_chat_session, :active, agent: agent) }

    it 'transfers to the new agent' do
      Escalated::Services::ChatSessionService.transfer_chat(session, new_agent.id)
      session.reload

      expect(session.agent_id).to eq(new_agent.id)
    end
  end

  describe 'agent status management' do
    it 'updates agent chat status' do
      profile = Escalated::AgentProfile.find_by(user_id: agent.id)
      profile.update!(chat_status: 'away')

      expect(profile.reload.chat_status).to eq('away')
    end

    it 'validates chat status values' do
      profile = Escalated::AgentProfile.find_by(user_id: agent.id)
      profile.chat_status = 'invalid'
      expect(profile).not_to be_valid
    end
  end

  describe 'sending a message' do
    let(:session) { create(:escalated_chat_session, :active, agent: agent) }

    it 'creates a reply as the agent' do
      reply = Escalated::Services::ChatSessionService.send_message(
        session,
        body: 'How can I help?',
        author: agent
      )

      expect(reply.body).to eq('How can I help?')
      expect(reply.author).to eq(agent)
    end
  end

  describe 'typing indicator' do
    let(:session) { create(:escalated_chat_session, :active, agent: agent) }

    it 'updates agent typing timestamp' do
      Escalated::Services::ChatSessionService.update_typing(session, is_agent: true)
      expect(session.reload.agent_typing_at).to be_present
    end
  end
end
