# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Escalated::WidgetChatController' do
  before do
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)
    allow(Escalated::Broadcasting).to receive(:broadcast)
  end

  describe 'chat availability' do
    it 'reports available when agents are online' do
      agent = create(:user, :agent)
      create(:escalated_agent_profile, user: agent, chat_status: 'online')

      routing = Escalated::Services::ChatRoutingService.evaluate_routing
      expect(routing[:available]).to be(true)
    end

    it 'reports unavailable when no agents are online' do
      routing = Escalated::Services::ChatRoutingService.evaluate_routing
      expect(routing[:available]).to be(false)
    end

    it 'reports queue size' do
      create(:escalated_chat_session, :waiting)
      create(:escalated_chat_session, :waiting)

      routing = Escalated::Services::ChatRoutingService.evaluate_routing
      expect(routing[:queue_size]).to eq(2)
    end
  end

  describe 'starting a chat' do
    it 'creates a chat ticket and session with correct attributes' do
      ticket = create(:escalated_ticket,
                      subject: 'Help needed',
                      channel: 'chat',
                      metadata: { 'source' => 'chat' })
      session = create(:escalated_chat_session,
                       ticket: ticket,
                       customer_session_id: 'sess_123',
                       status: 'waiting')

      expect(ticket).to be_persisted
      expect(ticket.channel).to eq('chat')
      expect(ticket.metadata['source']).to eq('chat')
      expect(session).to be_persisted
      expect(session.customer_session_id).to eq('sess_123')
      expect(session.status).to eq('waiting')
    end

    it 'generates a session_id via factory' do
      ticket = create(:escalated_ticket, channel: 'chat')
      session = create(:escalated_chat_session, ticket: ticket)

      expect(session.customer_session_id).to be_present
      expect(session.customer_session_id.length).to be > 0
    end
  end

  describe 'sending a message' do
    let(:session) { create(:escalated_chat_session, :active) }

    it 'creates a reply on the chat ticket' do
      expect do
        Escalated::Reply.create!(
          ticket: session.ticket,
          body: 'Hello from widget',
          author: nil,
          is_internal: false,
          is_system: false,
          is_pinned: false
        )
      end.to change(Escalated::Reply, :count).by(1)

      reply = session.ticket.replies.last
      expect(reply.body).to eq('Hello from widget')
    end
  end

  describe 'ending a chat' do
    let(:session) { create(:escalated_chat_session, :active) }

    it 'ends the session and resolves the ticket' do
      Escalated::Services::ChatSessionService.end_chat(session)
      session.reload

      expect(session.status).to eq('ended')
      expect(session.ticket.reload.status).to eq('resolved')
    end
  end

  describe 'rating a chat' do
    let(:session) { create(:escalated_chat_session, :ended) }

    it 'sets the rating on the session' do
      Escalated::Services::ChatSessionService.rate_chat(session, rating: 5, comment: 'Great!')
      session.reload

      expect(session.rating).to eq(5)
      expect(session.rating_comment).to eq('Great!')
    end

    it 'validates rating range' do
      session_obj = build(:escalated_chat_session, rating: 0)
      expect(session_obj).not_to be_valid
    end
  end
end
