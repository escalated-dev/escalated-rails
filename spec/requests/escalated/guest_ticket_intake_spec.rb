# frozen_string_literal: true

require 'rails_helper'

# Tickets that arrive without a signed-in user: the widget, the guest portal
# and live chat. Regression specs for the 2026-10-20 audit.
RSpec.describe 'Guest ticket intake', type: :request do
  let(:shop) { 'https://shop.example.com' }
  let(:json_headers) { { 'CONTENT_TYPE' => 'application/json', 'ACCEPT' => 'application/json' } }
  let(:created_events) { [] }

  before do
    Rails.cache.clear
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil,
                                                       widget_allowed_origins: [shop])
    allow(Escalated::Broadcasting).to receive(:broadcast)
    Escalated::EscalatedSetting.set('widget_enabled', '1')
  end

  around do |example|
    subscription = ActiveSupport::Notifications.subscribe('escalated.notification.ticket_created') do |*, payload|
      created_events << payload[:ticket]
    end
    example.run
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
    Rails.cache.clear
  end

  def post_json(path, payload, headers = {})
    post path, params: payload.to_json, headers: json_headers.merge(headers)
  end

  describe 'POST /widget/tickets' do
    let(:payload) do
      { name: 'Jane Doe', email: 'jane@example.com', subject: 'Order missing', description: 'It never came.' }
    end

    it 'keeps the guest name, email, contact and an expiring grant on the ticket' do
      post_json('/support/widget/tickets', payload.merge(guest_proof('jane@example.com')))

      expect(response).to have_http_status(:created)
      grant = response.parsed_body['guest_access_token']

      ticket = Escalated::Ticket.find_by!(reference: response.parsed_body['reference'])
      expect(Escalated::GuestAccess.resolve(grant)).to eq(ticket)
      expect(ticket).to have_attributes(guest_name: 'Jane Doe', guest_email: 'jane@example.com', guest_token: nil)
      expect(ticket.contact).to have_attributes(email: 'jane@example.com')
      expect(created_events).to eq([ticket])
    end

    it 'routes the ticket to the configured user in guest_user policy mode' do
      host_user = create(:user)
      Escalated::EscalatedSetting.set('guest_policy_mode', 'guest_user')
      Escalated::EscalatedSetting.set('guest_policy_user_id', host_user.id.to_s)

      post_json('/support/widget/tickets', payload.merge(guest_proof('jane@example.com')))

      ticket = Escalated::Ticket.find_by!(reference: response.parsed_body['reference'])
      expect(ticket.requester).to eq(host_user)
      expect(ticket.guest_email).to eq('jane@example.com')
    end
  end

  describe 'POST /guest' do
    it 'emits ticket_created and attaches the SLA policy' do
      allow(Escalated.configuration).to receive(:sla_enabled?).and_return(true)
      policy = create(:escalated_sla_policy, is_default: true)

      proof = guest_proof('sam@example.com', 'ticket', prefix: '/support/guest')
      post '/support/guest', params: { guest_name: 'Sam', guest_email: 'sam@example.com', subject: 'Help',
                                       description: 'Something broke.' }.merge(proof)

      ticket = Escalated::Ticket.order(:id).last
      expect(ticket).to have_attributes(guest_email: 'sam@example.com', sla_policy_id: policy.id)
      expect(Escalated::GuestAccess.active?(ticket)).to be(true)
      expect(created_events).to eq([ticket])
    end
  end

  describe 'live chat' do
    it 'emits ticket_created for the chat ticket' do
      post_json('/support/widget/chat/start',
                { name: 'Ann', email: 'ann@example.com', message: 'Hi' }.merge(guest_proof('ann@example.com', 'chat')))

      expect(response).to have_http_status(:created)
      ticket = Escalated::Ticket.find(response.parsed_body['ticket_id'])
      expect(ticket).to have_attributes(channel: 'chat', guest_email: 'ann@example.com')
      expect(ticket.contact).to be_present
      expect(created_events).to eq([ticket])
    end

    it 'refuses chat while the widget is off' do
      Escalated::EscalatedSetting.set('widget_enabled', '0')

      post_json('/support/widget/chat/start', { name: 'Ann', email: 'ann@example.com' })

      expect(response).to have_http_status(:forbidden)
      expect(Escalated::Ticket.count).to eq(0)
    end

    it 'refuses to start a chat while chat is off, and reports it unavailable' do
      Escalated::EscalatedSetting.set('chat_enabled', '0')

      post_json('/support/widget/chat/start', { name: 'Ann', email: 'ann@example.com' })
      expect(response).to have_http_status(:forbidden)

      get '/support/widget/chat/availability', headers: json_headers
      expect(response.parsed_body).to include('available' => false)
    end

    it 'applies the guest submission throttle to chat start' do
      allow(Escalated.configuration).to receive(:guest_rate_limit_settings)
        .and_return(enabled: true, tickets_per_minute: 1, replies_per_minute: 10, cache_store: Rails.cache)

      post_json('/support/widget/chat/start', { name: 'Ann', email: 'ann@example.com' })
      post_json('/support/widget/chat/start', { name: 'Ann', email: 'ann@example.com' })

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'answers 422 JSON for an empty message and for an ended chat' do
      post_json('/support/widget/chat/start',
                { name: 'Ann', email: 'ann@example.com' }.merge(guest_proof('ann@example.com', 'chat')))
      token = response.parsed_body['id']

      post_json("/support/widget/chat/#{token}/message", { body: '  ' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['message']).to be_present

      Escalated::ChatSession.for_visitor_token(token).update!(status: 'ended', ended_at: Time.current)
      post_json("/support/widget/chat/#{token}/message", { body: 'Still there?' })
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'CSRF' do
    around do |example|
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = original
    end

    let(:payload) { { name: 'Eve', email: 'eve@example.com', subject: 'Spam', description: 'Spam' } }

    it 'rejects a token-less POST from a site that is not allowed' do
      post_json('/support/widget/tickets', payload, 'Origin' => 'https://evil.example')

      expect(response.status).to be >= 400
      expect(Escalated::Ticket.count).to eq(0)
    end

    it 'accepts a POST from an allowed embedding site without a token' do
      proof = guest_proof('eve@example.com', headers: { 'Origin' => shop })
      post_json('/support/widget/tickets', payload.merge(proof), 'Origin' => shop)

      expect(response).to have_http_status(:created)
    end
  end

  describe 'widget knowledge base' do
    before { create(:escalated_article, :published, title: 'Secret plan', slug: 'secret-plan') }

    it 'answers 404 when the knowledge base is off' do
      Escalated::EscalatedSetting.set('knowledge_base_enabled', '0')

      get '/support/widget/articles?q=Secret', headers: json_headers
      expect(response).to have_http_status(:not_found)
      get '/support/widget/articles/secret-plan', headers: json_headers
      expect(response).to have_http_status(:not_found)
    end

    it 'answers 403 to a guest when the knowledge base is not public, and says so in /config' do
      Escalated::EscalatedSetting.set('knowledge_base_public', '0')

      get '/support/widget/articles?q=Secret', headers: json_headers
      expect(response).to have_http_status(:forbidden)
      get '/support/widget/articles/secret-plan', headers: json_headers
      expect(response).to have_http_status(:forbidden)

      get '/support/widget/config', headers: json_headers
      expect(response.parsed_body['kb_enabled']).to be(false)
    end
  end
end
