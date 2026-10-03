# frozen_string_literal: true

require 'rails_helper'

# The mail adapters live under lib/, which Rails does not autoload, so the
# webhook only works when lib/escalated.rb requires them.
RSpec.describe 'Inbound email webhook', type: :request do
  let(:signing_key) { 'mailgun-key' }

  before do
    allow(Escalated.configuration).to receive_messages(
      notification_channels: [],
      webhook_url: nil,
      inbound_email_enabled: true,
      inbound_email_adapter: :mailgun,
      mailgun_signing_key: signing_key
    )
  end

  it 'turns a signed Mailgun post into a ticket' do
    timestamp = Time.current.to_i.to_s
    token = SecureRandom.hex(16)

    expect do
      post '/support/inbound/mailgun', params: {
        timestamp: timestamp,
        token: token,
        signature: OpenSSL::HMAC.hexdigest('SHA256', signing_key, "#{timestamp}#{token}"),
        from: 'Jane Doe <jane@example.com>',
        recipient: 'support@example.com',
        subject: 'Printer on fire',
        'body-plain' => 'Please help.',
        'Message-Id' => '<abc123@mail.example.com>'
      }
    end.to change(Escalated::Ticket, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['status']).to eq('processed')
  end
end
