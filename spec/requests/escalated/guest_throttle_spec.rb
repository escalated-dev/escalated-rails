# frozen_string_literal: true

require 'rails_helper'

# Per-client-IP rate limit on the unauthenticated guest endpoints, mirroring
# escalated-nestjs#130: 5 guest ticket submissions and 10 guest replies per IP
# per minute by default, in separate buckets. The reply throttle runs before
# the guest-token lookup so wrong-token requests count too.
RSpec.describe 'Guest endpoint rate limit', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:ticket_params) do
    { name: 'Guest', email: 'guest@example.com', subject: 'Help', description: 'It broke' }
  end
  let(:guest_ticket) { create(:escalated_ticket, guest_token: 'a' * 64, guest_email: 'guest@example.com') }

  before do
    Rails.cache.clear
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    allow(Escalated::EscalatedSetting).to receive(:guest_tickets_enabled?).and_return(true)
    Escalated::EscalatedSetting.set('widget_enabled', '1')
  end

  after { Rails.cache.clear }

  # The window is a clock-aligned 60s bucket; pin the clock mid-minute so an
  # example never straddles two buckets.
  around { |example| travel_to(Time.zone.parse('2026-01-01 12:00:15')) { example.run } }

  def guest_rate_limit(**settings)
    allow(Escalated.configuration).to receive(:guest_rate_limit).and_return(settings)
  end

  def widget_ticket(ip: '203.0.113.1')
    post '/support/widget/tickets', params: ticket_params, env: { 'REMOTE_ADDR' => ip }
    response.status
  end

  def guest_form_ticket(ip: '203.0.113.1')
    post '/support/guest', params: ticket_params, env: { 'REMOTE_ADDR' => ip }
    response.status
  end

  def guest_reply(token, ip: '203.0.113.1')
    post "/support/guest/#{token}/reply", params: { body: 'Any news?' }, env: { 'REMOTE_ADDR' => ip }
    response.status
  end

  describe 'guest ticket creation' do
    it 'allows 5 widget tickets per minute per IP and rejects the 6th with 429' do
      statuses = Array.new(6) { widget_ticket }

      expect(statuses).to eq([201, 201, 201, 201, 201, 429])
      expect(Escalated::Ticket.count).to eq(5)
    end

    it 'allows 5 guest-form tickets per minute per IP and rejects the 6th with 429' do
      statuses = Array.new(6) { guest_form_ticket }

      expect(statuses).to eq([302, 302, 302, 302, 302, 429])
      expect(Escalated::Ticket.count).to eq(5)
    end

    it 'counts the widget and the guest form in one ticket bucket' do
      3.times { widget_ticket }

      expect(Array.new(3) { guest_form_ticket }).to eq([302, 302, 429])
    end

    it 'sends Retry-After with the 429' do
      5.times { widget_ticket }
      widget_ticket

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers['Retry-After'].to_i).to be_between(1, 60)
    end

    it 'keys each client IP separately' do
      5.times { widget_ticket(ip: '203.0.113.1') }

      expect(widget_ticket(ip: '203.0.113.2')).to eq(201)
    end

    it 'honours a configured ticket limit' do
      guest_rate_limit(tickets_per_minute: 2)

      expect(Array.new(3) { widget_ticket }).to eq([201, 201, 429])
    end

    it 'never returns 429 when disabled' do
      guest_rate_limit(enabled: false)

      expect(Array.new(20) { guest_form_ticket }).not_to include(429)
    end
  end

  describe 'guest replies' do
    it 'allows 10 replies per minute per IP and rejects the 11th with 429' do
      token = guest_ticket.guest_token
      statuses = Array.new(11) { guest_reply(token) }

      expect(statuses).to eq(([302] * 10) + [429])
      expect(response.headers['Retry-After'].to_i).to be_between(1, 60)
    end

    it 'counts requests with a wrong guest token' do
      guest_rate_limit(replies_per_minute: 3)
      statuses = Array.new(3) { guest_reply('wrong-token') }
      statuses << guest_reply(guest_ticket.guest_token)

      expect(statuses).to eq([404, 404, 404, 429])
    end

    it 'honours a configured reply limit' do
      guest_rate_limit(replies_per_minute: 1)
      token = guest_ticket.guest_token

      expect(Array.new(2) { guest_reply(token) }).to eq([302, 429])
    end

    it 'keeps the default for a limit the host left unset' do
      guest_rate_limit(replies_per_minute: 1)

      expect(Array.new(6) { widget_ticket }).to eq([201, 201, 201, 201, 201, 429])
    end

    it 'counts tickets and replies in separate buckets' do
      5.times { widget_ticket }

      expect(guest_reply(guest_ticket.guest_token)).to eq(302)
    end

    it 'never returns 429 when disabled' do
      guest_rate_limit(enabled: false)
      token = guest_ticket.guest_token

      expect(Array.new(20) { guest_reply(token) }).not_to include(429)
    end
  end

  describe 'counter store' do
    it 'counts in a host-supplied cache store' do
      store = ActiveSupport::Cache::MemoryStore.new
      guest_rate_limit(tickets_per_minute: 1, cache_store: store)

      expect(widget_ticket).to eq(201)
      # Clearing Rails.cache must not reset a counter kept in the host's store.
      Rails.cache.clear
      expect(widget_ticket).to eq(429)
    end
  end
end
