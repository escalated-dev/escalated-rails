# frozen_string_literal: true

require 'openssl'
require 'rails_helper'
require 'webmock'
require 'webmock/rspec/matchers'

# The two other places Escalated POSTs to a URL: the webhook_url a host sets in
# its initializer, and a workflow's send_webhook action.
RSpec.describe 'Outbound webhook requests' do # rubocop:disable RSpec/DescribeClass
  include WebMock::API
  include WebMock::Matchers

  let(:ticket) { create(:escalated_ticket) }

  before do
    WebMock.enable!
    WebMock.disable_net_connect!
    allow(Addrinfo).to receive(:getaddrinfo).and_return([instance_double(Addrinfo, ip_address: '93.184.215.14')])
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
  end

  after do
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  describe 'the configured webhook_url' do
    let(:url) { 'https://hooks.example.test/escalated?key=abc' }

    before do
      allow(Escalated.configuration).to receive_messages(webhook_url: url, hosted_api_key: nil)
      # send_webhook posts from a thread; run it inline so the request has been
      # made by the time the example looks for it.
      allow(Thread).to receive(:new).and_yield
    end

    it 'posts to the path and the query string' do
      stub = stub_request(:post, url).to_return(status: 200)

      Escalated::Services::NotificationService.send_webhook(:ticket_created, ticket: ticket)

      expect(stub).to have_been_requested.once
    end

    it 'sends no signature rather than one made with a key published in the source' do
      stub_request(:post, url).to_return(status: 200)

      Escalated::Services::NotificationService.send_webhook(:ticket_created, ticket: ticket)

      expect(a_request(:post, url).with { |request| !request.headers.key?('X-Escalated-Signature') })
        .to have_been_made.once
    end

    it 'signs with the configured webhook_secret' do
      allow(Escalated.configuration).to receive(:webhook_secret).and_return('host-secret')
      stub_request(:post, url).to_return(status: 200)

      Escalated::Services::NotificationService.send_webhook(:ticket_created, ticket: ticket)

      expect(
        a_request(:post, url).with do |request|
          request.headers['X-Escalated-Signature'] == OpenSSL::HMAC.hexdigest('SHA256', 'host-secret', request.body)
        end
      ).to have_been_made.once
    end
  end

  describe 'the workflow send_webhook action' do
    let(:engine) { Escalated::WorkflowEngine.new }

    it 'posts to the path and the query string' do
      stub = stub_request(:post, 'https://hooks.example.test/flow?key=abc').to_return(status: 200)

      engine.send(:send_webhook, { 'type' => 'send_webhook', 'value' => 'https://hooks.example.test/flow?key=abc' },
                  ticket)

      expect(stub).to have_been_requested.once
    end

    it 'refuses an address inside the server’s own network' do
      action = { 'type' => 'send_webhook', 'value' => 'http://169.254.169.254/latest/meta-data/' }

      expect { engine.send(:send_webhook, action, ticket) }.to raise_error(/private, loopback or link-local/)
      expect(a_request(:any, /169\.254\.169\.254/)).not_to have_been_made
    end
  end
end
