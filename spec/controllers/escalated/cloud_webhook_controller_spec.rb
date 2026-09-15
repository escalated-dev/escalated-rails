# frozen_string_literal: true

require 'json'
require 'openssl'
require 'rails_helper'

RSpec.describe 'Escalated::CloudWebhookController', type: :request do
  let(:secret) { 'whsec_site' }
  let(:ticket) { create(:escalated_ticket, subject: 'Before', description: 'Body', status: 'open', priority: 'medium') }

  before do
    allow(Escalated.configuration).to receive_messages(hosted_signing_secret: secret, notification_channels: [])
    Rails.cache.clear
  end

  def projected(overrides = {})
    {
      id: 501, ticket_number: 7, subject: ticket.subject, description: ticket.description,
      status: 'open', priority: 'normal', assigned_to: nil, external_id: ticket.reference,
      metadata: { origin: 'synced', source_site_id: 1 }
    }.merge(overrides)
  end

  def post_event(event, ticket_payload, event_id: 'evt-1', sign_with: secret)
    body = { event: event, event_id: event_id, ticket: ticket_payload, timestamp: Time.current.iso8601 }.to_json
    headers = { 'CONTENT_TYPE' => 'application/json', 'ACCEPT' => 'application/json' }
    headers['X-Escalated-Signature'] = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', sign_with, body)}" if sign_with
    post '/support/cloud/webhook', params: body, headers: headers
    response.parsed_body
  end

  it 'answers 503 until a signing secret is configured' do
    allow(Escalated.configuration).to receive(:hosted_signing_secret).and_return(nil)
    post_event('ticket.updated', projected)
    expect(response).to have_http_status(:service_unavailable)
  end

  it 'rejects a missing or wrong signature' do
    post_event('ticket.updated', projected(status: 'closed'), sign_with: nil)
    expect(response).to have_http_status(:unauthorized)
    post_event('ticket.updated', projected(status: 'closed'), sign_with: 'other')
    expect(response).to have_http_status(:unauthorized)
    expect(ticket.reload.status).to eq('open')
  end

  it 'applies a cloud status change through the local driver with the package vocabulary' do
    body = post_event('ticket.status_changed', projected(status: 'waiting'))
    expect(response).to have_http_status(:ok)
    expect(body).to include('received' => true, 'applied' => true, 'changes' => ['status'])
    expect(ticket.reload.status).to eq('waiting_on_customer')
  end

  it 'applies subject, description and priority from ticket.updated and logs activity without an actor' do
    body = post_event('ticket.updated', projected(subject: 'After', description: 'New body', priority: 'urgent'))
    expect(body['changes']).to contain_exactly('subject', 'description', 'priority')
    ticket.reload
    expect(ticket.subject).to eq('After')
    expect(ticket.description).to eq('New body')
    expect(ticket.priority).to eq('urgent')
    expect(ticket.activities.where(action: 'priority_changed').count).to eq(1)
  end

  it 'reports nothing applied when the projection matches the ticket' do
    body = post_event('ticket.updated', projected)
    expect(body).to include('applied' => false, 'changes' => [])
  end

  it 'ignores a replayed event id' do
    post_event('ticket.status_changed', projected(status: 'closed'), event_id: 'evt-dup')
    body = post_event('ticket.status_changed', projected(status: 'open'), event_id: 'evt-dup')
    expect(body).to include('received' => true, 'applied' => false, 'replay' => true)
    expect(ticket.reload.status).to eq('closed')
  end

  it 'ignores events it does not apply, tickets without external_id and unknown references' do
    body = post_event('ticket.created', projected(status: 'closed'), event_id: 'evt-created')
    expect(response).to have_http_status(:accepted)
    expect(body['applied']).to be(false)

    post_event('ticket.updated', projected(status: 'closed', external_id: nil), event_id: 'evt-no-external')
    expect(response).to have_http_status(:accepted)

    post_event('ticket.updated', projected(status: 'closed', external_id: 'ESC-NOPE'), event_id: 'evt-unknown')
    expect(response).to have_http_status(:accepted)
    expect(ticket.reload.status).to eq('open')
  end

  it 'never echoes the change back to the cloud' do
    allow(Escalated.configuration).to receive(:mode).and_return(:synced)
    expect(Escalated::Drivers::HostedApiClient).not_to receive(:new)
    post_event('ticket.status_changed', projected(status: 'resolved'))
    expect(ticket.reload.status).to eq('resolved')
  end
end
