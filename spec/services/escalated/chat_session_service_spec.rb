# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Services::ChatSessionService do
  let(:agent) { create(:user, :agent) }
  let(:agent_profile) { create(:escalated_agent_profile, user: agent, chat_status: 'online') }

  before do
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)
  end

  describe '.start_chat' do
    let(:params) do
      {
        subject: 'Help with billing',
        message: 'I need help with my invoice',
        name: 'John Doe',
        email: 'john@example.com',
        session_id: 'abc123'
      }
    end

    it 'creates a ticket with chat channel' do
      result = described_class.start_chat(params)
      expect(result[:ticket]).to be_a(Escalated::Ticket)
      expect(result[:ticket].channel).to eq('chat')
      expect(result[:ticket]).to be_persisted
    end

    it 'creates a chat session in waiting state' do
      result = described_class.start_chat(params)
      expect(result[:session]).to be_a(Escalated::ChatSession)
      expect(result[:session].status).to eq('waiting')
      expect(result[:session].customer_session_id).to eq('abc123')
    end

    it 'sets ticket metadata with chat source' do
      result = described_class.start_chat(params)
      expect(result[:ticket].metadata).to include('source' => 'chat')
    end

    it 'auto-assigns when an agent is available' do
      agent_profile # ensure agent profile exists
      result = described_class.start_chat(params)
      expect(result[:session].reload.agent_id).to eq(agent.id)
      expect(result[:session].status).to eq('active')
    end

    it 'stays in waiting when no agent available' do
      result = described_class.start_chat(params)
      # No agent profile with online status exists
      expect(result[:session].status).to eq('waiting')
    end
  end

  describe '.assign_agent' do
    let(:session) { create(:escalated_chat_session, :waiting) }

    it 'assigns the agent to the session' do
      described_class.assign_agent(session, agent.id)
      session.reload
      expect(session.agent_id).to eq(agent.id)
      expect(session.status).to eq('active')
      expect(session.started_at).to be_present
    end

    it 'updates the ticket assignee' do
      described_class.assign_agent(session, agent.id)
      expect(session.ticket.reload.assigned_to).to eq(agent.id)
    end

    it 'sets the ticket status to in_progress' do
      described_class.assign_agent(session, agent.id)
      expect(session.ticket.reload.status).to eq('in_progress')
    end
  end

  describe '.end_chat' do
    let(:session) { create(:escalated_chat_session, :active, agent: agent) }

    it 'ends the session' do
      described_class.end_chat(session)
      session.reload
      expect(session.status).to eq('ended')
      expect(session.ended_at).to be_present
    end

    it 'resolves the ticket' do
      described_class.end_chat(session)
      ticket = session.ticket.reload
      expect(ticket.status).to eq('resolved')
      expect(ticket.resolved_at).to be_present
      expect(ticket.chat_ended_at).to be_present
    end
  end

  describe '.transfer_chat' do
    let(:new_agent) { create(:user, :agent) }
    let(:session) { create(:escalated_chat_session, :active, agent: agent) }

    it 'transfers to the new agent' do
      described_class.transfer_chat(session, new_agent.id)
      session.reload
      expect(session.agent_id).to eq(new_agent.id)
      expect(session.status).to eq('active')
    end

    it 'updates the ticket assignee' do
      described_class.transfer_chat(session, new_agent.id)
      expect(session.ticket.reload.assigned_to).to eq(new_agent.id)
    end
  end

  describe '.send_message' do
    let(:session) { create(:escalated_chat_session, :active, agent: agent) }

    it 'creates a reply on the ticket' do
      reply = described_class.send_message(session, body: 'Hello!', author: agent)
      expect(reply).to be_a(Escalated::Reply)
      expect(reply.body).to eq('Hello!')
      expect(reply.ticket).to eq(session.ticket)
    end

    it 'creates an internal reply when specified' do
      reply = described_class.send_message(session, body: 'Internal note', author: agent, is_internal: true)
      expect(reply.is_internal).to be(true)
    end
  end

  describe '.update_typing' do
    let(:session) { create(:escalated_chat_session, :active, agent: agent) }

    it 'updates agent typing timestamp' do
      described_class.update_typing(session, is_agent: true)
      expect(session.reload.agent_typing_at).to be_present
    end

    it 'updates customer typing timestamp' do
      described_class.update_typing(session, is_agent: false)
      expect(session.reload.customer_typing_at).to be_present
    end
  end

  describe '.rate_chat' do
    let(:session) { create(:escalated_chat_session, :ended) }

    it 'sets the rating' do
      described_class.rate_chat(session, rating: 5, comment: 'Excellent!')
      session.reload
      expect(session.rating).to eq(5)
      expect(session.rating_comment).to eq('Excellent!')
    end
  end
end
