# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

RSpec.describe Escalated::Drivers::HostedApiClient do
  let(:events_url) { 'https://cloud.example.test/api/v1/events' }

  before do
    WebMock.enable!
    WebMock.disable_net_connect!(allow_localhost: true)
    allow(Escalated.configuration).to receive_messages(
      hosted_api_url: 'https://cloud.example.test/api/v1',
      hosted_api_key: 'sync-token'
    )
  end

  after(:all) do
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  describe '.emit' do
    it 'posts driver actions to /events as named cloud events with a stable event id' do
      stub = stub_request(:post, events_url)
        .to_return(status: 200, body: '{"received":true}', headers: { 'Content-Type' => 'application/json' })

      described_class.emit(:create_ticket, { reference: 'ESC-00007', subject: 'Hello' })

      expect(stub.with do |req|
        body = JSON.parse(req.body)
        body['event'] == 'ticket.created' &&
          body['payload'] == { 'reference' => 'ESC-00007', 'subject' => 'Hello' } &&
          body['event_id'].to_s.length == 36 &&
          body['timestamp'].present? &&
          req.headers['Authorization'] == 'Bearer sync-token'
      end).to have_been_requested.once
    end

    it 'reuses a caller-supplied event id so retries are recognised as the same event' do
      stub = stub_request(:post, events_url).to_return(status: 200, body: '{}')

      described_class.new.emit(:update_ticket, { reference: 'ESC-00007' }, event_id: 'evt-fixed')

      expect(stub.with { |req| JSON.parse(req.body)['event_id'] == 'evt-fixed' }).to have_been_requested.once
    end

    it 'names every driver action the cloud ingests' do
      expect(described_class::EVENT_NAMES.values).to match_array(
        %w[ticket.created ticket.updated ticket.status_changed ticket.assigned ticket.unassigned
           reply.created ticket.tags_added ticket.tags_removed ticket.department_changed ticket.priority_changed]
      )
    end

    it 're-raises cloud failures so SyncedDriver can log and continue' do
      stub_request(:post, events_url).to_return(status: 500, body: '{"message":"boom"}')

      expect { described_class.emit(:update_ticket, { reference: 'x' }) }
        .to raise_error(Escalated::Drivers::HostedApiClient::ApiError)
    end
  end
end
