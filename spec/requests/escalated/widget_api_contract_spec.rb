# frozen_string_literal: true

require 'rails_helper'

# The shared widget (@escalated-dev/escalated, src/widget/EscalatedWidget.vue)
# talks to these routes. Each example sends the request the widget sends and
# checks the fields the widget reads.
RSpec.describe 'Widget API used by the shared widget', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:base) { '/support/widget' }

  before do
    Rails.cache.clear
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)
    allow(Escalated::Broadcasting).to receive(:broadcast)
    Escalated::EscalatedSetting.set('widget_enabled', '1')
  end

  after { Rails.cache.clear }

  def post_json(path, payload = nil)
    headers = { 'CONTENT_TYPE' => 'application/json', 'ACCEPT' => 'application/json' }
    post path, params: payload&.to_json, headers: headers
  end

  def get_json(path)
    get path, headers: { 'ACCEPT' => 'application/json' }
  end

  describe 'GET /config' do
    it 'lists the active departments and the widget switches' do
      sales = create(:escalated_department, name: 'Sales')
      create(:escalated_department, :inactive, name: 'Archive')

      get_json("#{base}/config")

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['departments']).to eq([{ 'id' => sales.id, 'name' => 'Sales' }])
      expect(body).to include('enabled' => true, 'kb_enabled' => true, 'guest_tickets_enabled' => true,
                              'accepts_metadata' => true, 'status_lookup_enabled' => true,
                              'guest_verification_required' => true)
      expect(body).to include('color', 'position', 'greeting')
    end

    it 'answers 403 with enabled false while the widget is off' do
      Escalated::EscalatedSetting.set('widget_enabled', '0')

      get_json("#{base}/config")

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['enabled']).to be(false)
    end
  end

  describe 'GET /articles' do
    it 'wraps search results in an articles key' do
      create(:escalated_article, :published, title: 'Reset your password', slug: 'reset-password')
      create(:escalated_article, title: 'Reset draft', slug: 'reset-draft')

      get_json("#{base}/articles?q=#{CGI.escape('Reset')}")

      expect(response).to have_http_status(:ok)
      articles = response.parsed_body['articles']
      expect(articles.pluck('slug')).to eq(['reset-password'])
      expect(articles.first).to include('title' => 'Reset your password', 'excerpt' => be_a(String))
    end

    it 'returns the article the widget opens' do
      create(:escalated_article, :published, title: 'Billing', slug: 'billing', body: '<p>Pay here</p>')

      get_json("#{base}/articles/billing")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('title' => 'Billing', 'slug' => 'billing', 'body' => '<p>Pay here</p>')
    end
  end

  describe 'POST /tickets' do
    let(:ticket_params) do
      { name: 'Jane Doe', email: 'jane@example.com', subject: 'Order', description: 'Where is it?' }
    end

    it 'files the ticket in the chosen department and returns its reference' do
      department = create(:escalated_department)

      post_json("#{base}/tickets",
                ticket_params.merge(department_id: department.id, metadata: nil).merge(guest_proof('jane@example.com')))

      expect(response).to have_http_status(:created)
      reference = response.parsed_body['reference']
      expect(reference).to be_present
      expect(response.parsed_body['message']).to be_present
      expect(Escalated::Ticket.find_by!(reference: reference).department_id).to eq(department.id)
    end

    it 'accepts the null department the widget sends when none is picked' do
      post_json("#{base}/tickets", ticket_params.merge(department_id: nil).merge(guest_proof('jane@example.com')))

      expect(response).to have_http_status(:created)
      expect(Escalated::Ticket.find_by!(reference: response.parsed_body['reference']).department_id).to be_nil
    end

    it 'rejects an unknown or inactive department with a field error' do
      inactive = create(:escalated_department, :inactive)

      [inactive.id, 999_999].each do |department_id|
        post_json("#{base}/tickets", ticket_params.merge(department_id: department_id))

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['errors']).to have_key('department_id')
        expect(response.parsed_body['message']).to be_present
      end
      expect(Escalated::Ticket.count).to eq(0)
    end
  end

  describe 'live chat' do
    let(:agent) { create(:user, :agent, name: 'Agent Smith') }

    def start_chat(extra = {})
      post_json("#{base}/chat/start", { name: 'John Doe', email: 'john@example.com', department_id: nil,
                                        message: 'Hello' }.merge(guest_proof('john@example.com', 'chat'), extra))
      response.parsed_body
    end

    it 'starts a chat whose id is the unguessable customer token' do
      body = start_chat

      expect(response).to have_http_status(:created)
      session = Escalated::ChatSession.find_by!(customer_session_id: Escalated::ChatSession.digest(body['id']))
      expect(body['id']).to match(/\A\h{32}\z/)
      expect(body['status']).to eq('waiting')
      expect(body['messages']).to eq([])
      expect(session).to be_present
    end

    it 'answers start with the same fields as escalated-laravel' do
      body = start_chat
      ticket = Escalated::Ticket.last

      expect(response).to have_http_status(:created)
      # `id` and `session_id` are both the chat token, as in Laravel.
      expect(body['session_id']).to eq(body['id'])
      expect(Time.iso8601(body['expires_at'])).to be > Time.current
      expect(body['ticket_reference']).to eq(ticket.reference)
      expect(body['status']).to eq('waiting')
      expect(body).to have_key('agent_name')
      expect(body['agent_name']).to be_nil
      # The internal numeric ids the token replaced are not exposed.
      expect(body).not_to have_key('ticket_id')
    end

    it 'never lets the browser choose the chat token' do
      victim = start_chat
      body = start_chat(session_id: victim['id'])

      expect(response).to have_http_status(:created)
      expect(body['id']).not_to eq(victim['id'])
      expect(body['id']).to match(/\A\h{32}\z/)
    end

    it 'rejects an unknown department when starting a chat' do
      start_chat(department_id: 999_999)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['errors']).to have_key('department_id')
      expect(Escalated::ChatSession.count).to eq(0)
    end

    it 'sends and lists messages through the id path' do
      id = start_chat['id']
      session = Escalated::ChatSession.for_visitor_token(id)

      post_json("#{base}/chat/#{id}/messages", { body: 'Is anyone there?' })
      expect(response).to have_http_status(:ok)

      Escalated::Services::ChatSessionService.assign_agent(session, agent.id)
      Escalated::Services::ChatSessionService.send_message(session.reload, body: 'Hi John', author: agent)
      Escalated::Services::ChatSessionService.update_typing(session, is_agent: true)

      get_json("#{base}/chat/#{id}/messages")
      expect(response).to have_http_status(:ok)
      data = response.parsed_body
      expect(data['messages'].map { |m| m.slice('body', 'is_agent', 'author') }).to eq(
        [
          { 'body' => 'Is anyone there?', 'is_agent' => false, 'author' => { 'name' => 'John Doe' } },
          { 'body' => 'Hi John', 'is_agent' => true, 'author' => { 'name' => 'Agent Smith' } }
        ]
      )
      expect(data['messages']).to all(include('id', 'created_at'))
      expect(data).to include('agent' => { 'name' => 'Agent Smith' }, 'typing' => 'Agent Smith', 'ended' => false)
    end

    it 'types, ends and rates through the id path' do
      id = start_chat['id']
      session = Escalated::ChatSession.for_visitor_token(id)

      post_json("#{base}/chat/#{id}/typing")
      expect(response).to have_http_status(:success)
      expect(session.reload.customer_typing_at).to be_present

      post_json("#{base}/chat/#{id}/end")
      expect(response).to have_http_status(:success)
      get_json("#{base}/chat/#{id}/messages")
      expect(response.parsed_body['ended']).to be(true)

      post_json("#{base}/chat/#{id}/rate", { rating: 5, comment: 'Great' })
      expect(response).to have_http_status(:success)
      expect(session.reload).to have_attributes(rating: 5, rating_comment: 'Great')
    end

    it 'keeps the older singular message route working' do
      id = start_chat['id']

      post_json("#{base}/chat/#{id}/message", { body: 'Still here' })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['body']).to eq('Still here')
    end

    it 'answers 404 for a token it does not know' do
      start_chat

      %w[messages typing end rate].each do |action|
        post_json("#{base}/chat/not-a-real-token/#{action}", { body: 'x', rating: 5 })
        expect(response).to have_http_status(:not_found)
      end
      get_json("#{base}/chat/not-a-real-token/messages")
      expect(response).to have_http_status(:not_found)
    end

    it 'issues an expiring token and stores only its hash' do
      freeze_time do
        body = start_chat

        expect(Time.zone.parse(body['expires_at'])).to eq(Escalated::GuestAccess.ttl.from_now.change(usec: 0))
        expect(Escalated::ChatSession.find_by(customer_session_id: body['id'])).to be_nil
        session = Escalated::ChatSession.find_by!(customer_session_id: Escalated::ChatSession.digest(body['id']))
        expect(session.customer_token_expires_at).to eq(Escalated::GuestAccess.ttl.from_now)
      end
    end

    it 'follows guest_access_ttl_minutes for the token lifetime' do
      allow(Escalated.configuration).to receive(:guest_access_ttl_minutes).and_return(30)
      freeze_time do
        expect(Time.zone.parse(start_chat['expires_at'])).to eq(30.minutes.from_now.change(usec: 0))
      end
    end

    it 'answers 404 on every chat route once the token has expired' do
      id = start_chat['id']

      travel(Escalated::GuestAccess.ttl + 1.minute) do
        %w[messages message typing end rate].each do |action|
          post_json("#{base}/chat/#{id}/#{action}", { body: 'x', rating: 5 })
          expect(response).to have_http_status(:not_found), action
        end
        get_json("#{base}/chat/#{id}/messages")
        expect(response).to have_http_status(:not_found)
      end
    end

    it 'keeps a chat started before tokens expired working, with a full lifetime' do
      id = start_chat['id']
      # The shape such a chat has after the migration: plain token, no expiry.
      Escalated::ChatSession.for_visitor_token(id).update_columns(customer_session_id: id,
                                                                  customer_token_expires_at: nil)

      freeze_time do
        get_json("#{base}/chat/#{id}/messages")
        expect(response).to have_http_status(:ok)
        session = Escalated::ChatSession.find_by!(customer_session_id: Escalated::ChatSession.digest(id))
        expect(session.customer_token_expires_at).to eq(Escalated::GuestAccess.ttl.from_now)
      end
    end

    it 'closes an ended chat to messages, typing and a second end, but keeps it readable and rateable' do
      id = start_chat['id']

      post_json("#{base}/chat/#{id}/rate", { rating: 5 })
      expect(response).to have_http_status(:unprocessable_content)

      post_json("#{base}/chat/#{id}/end")
      expect(response).to have_http_status(:ok)
      %w[messages typing end].each do |action|
        post_json("#{base}/chat/#{id}/#{action}", { body: 'late' })
        expect(response).to have_http_status(:unprocessable_content), action
      end
      get_json("#{base}/chat/#{id}/messages")
      expect(response.parsed_body['ended']).to be(true)
      post_json("#{base}/chat/#{id}/rate", { rating: 5 })
      expect(response).to have_http_status(:ok)
    end

    it 'never shows internal notes to the guest' do
      id = start_chat['id']
      session = Escalated::ChatSession.for_visitor_token(id)
      Escalated::Services::ChatSessionService.send_message(session, body: 'secret', author: agent, is_internal: true)

      get_json("#{base}/chat/#{id}/messages")

      expect(response.parsed_body['messages'].pluck('body')).not_to include('secret')
    end
  end
end
