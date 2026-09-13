# frozen_string_literal: true

require 'cgi'
require 'json'
require 'openssl'
require 'rails_helper'
require 'webmock'
require 'webmock/rspec/matchers'

# The Webhooks admin screen as the shared frontend drives it
# (src/pages/Admin/Webhooks/Index.vue, Form.vue, DeliveryLog.vue), and the
# deliveries those webhooks exist to produce when tickets change.
RSpec.describe 'Admin webhooks', type: :request do
  include ActiveJob::TestHelper
  include WebMock::API
  include WebMock::Matchers

  let(:admin) { create(:user, :admin, email: 'admin-webhooks@example.test') }
  let(:requester) { create(:user) }
  let(:hook_url) { 'https://hooks.example.test/escalated' }
  let(:form_body) do
    { url: hook_url, events: %w[ticket.created reply.created], secret: 'shared-secret', active: true }
  end

  before do
    WebMock.enable!
    WebMock.disable_net_connect!

    # Stand-in DNS, so nothing here depends on a real resolver.
    allow(Addrinfo).to receive(:getaddrinfo) do |host, *|
      address = {
        'hooks.example.test' => '93.184.215.14',
        'localhost' => '127.0.0.1',
        'intranet.example.test' => '10.20.30.40'
      }[host]
      raise SocketError, "getaddrinfo: Name or service not known (#{host})" unless address

      [instance_double(Addrinfo, ip_address: address)]
    end

    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(admin)
  end

  after do
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  # What an Inertia form visit sends: a JSON body and the X-Inertia header.
  def inertia_visit(method, path, body = nil, referer: nil)
    headers = { 'X-Inertia' => 'true' }
    headers['Referer'] = "http://www.example.com#{referer}" if referer
    send(method, path, params: body, headers: headers, as: :json)
  end

  # Inertia HTML responses JSON-encode the page inside data-page="..." (HTML-escaped).
  def inertia_page_from(body)
    encoded = body[%r{data-page="(.+?)"></div>}m, 1]
    raise 'missing Inertia page payload' unless encoded

    JSON.parse(CGI.unescapeHTML(encoded))
  end

  def create_webhook(**attributes)
    Escalated::Webhook.create!(
      { url: hook_url, events: ['ticket.created'], active: true, secret: 'shared-secret' }.merge(attributes)
    )
  end

  def create_ticket
    Escalated::Services::TicketService.create(subject: 'Printer on fire', description: 'Smoke.', requester: requester)
  end

  describe 'the list' do
    it 'shows each webhook with the fields the page reads' do
      webhook = create_webhook
      Escalated::WebhookDelivery.create!(webhook: webhook, event: 'ticket.created', payload: {},
                                         response_code: 204, attempts: 1)

      get '/support/admin/webhooks'

      expect(response).to have_http_status(:ok)
      page = inertia_page_from(response.body)
      expect(page['component']).to eq('Escalated/Admin/Webhooks/Index')

      row = page.dig('props', 'webhooks').sole
      expect(row).to include('id' => webhook.id, 'url' => hook_url, 'events' => ['ticket.created'], 'active' => true)
      expect(row.dig('deliveries', 0, 'response_code')).to eq(204)
      expect(row).not_to have_key('secret')
    end
  end

  describe 'the form' do
    it 'offers the events that are delivered' do
      get '/support/admin/webhooks/new'

      expect(response).to have_http_status(:ok)
      page = inertia_page_from(response.body)
      expect(page['component']).to eq('Escalated/Admin/Webhooks/Form')
      expect(page.dig('props', 'webhook')).to be_nil
      expect(page.dig('props', 'availableEvents')).to include('ticket.created', 'ticket.assigned', 'reply.created')
    end

    it 'fills in an existing webhook without handing its secret back' do
      webhook = create_webhook(events: %w[ticket.created reply.created], active: false)

      get "/support/admin/webhooks/#{webhook.id}/edit"

      expect(response).to have_http_status(:ok)
      page = inertia_page_from(response.body)
      expect(page['component']).to eq('Escalated/Admin/Webhooks/Form')
      expect(page.dig('props', 'webhook')).to include('id' => webhook.id, 'url' => hook_url,
                                                      'events' => %w[ticket.created reply.created], 'active' => false)
      expect(page.dig('props', 'webhook')).not_to have_key('secret')
    end
  end

  describe 'saving' do
    it 'creates a webhook from the body the form sends' do
      expect do
        inertia_visit(:post, '/support/admin/webhooks', form_body)
      end.to change(Escalated::Webhook, :count).by(1)

      expect(response).to redirect_to('/support/admin/webhooks')
      expect(Escalated::Webhook.last).to have_attributes(url: hook_url, events: %w[ticket.created reply.created],
                                                         secret: 'shared-secret', active: true)
    end

    it 'updates a webhook and keeps the stored secret when the form sends it blank' do
      webhook = create_webhook(secret: 'keep-me')

      inertia_visit(:put, "/support/admin/webhooks/#{webhook.id}",
                    form_body.merge(url: 'https://hooks.example.test/v2', secret: '', active: false))

      expect(response).to redirect_to('/support/admin/webhooks')
      expect(webhook.reload).to have_attributes(url: 'https://hooks.example.test/v2', active: false, secret: 'keep-me')
    end

    it 'refuses a URL that points into the server’s own network', :aggregate_failures do
      [
        'http://127.0.0.1/hook',
        'http://localhost:3000/hook',
        'http://169.254.169.254/latest/meta-data/',
        'http://10.0.0.5/hook',
        'http://[::1]/hook',
        'http://[::ffff:127.0.0.1]/hook',
        'http://intranet.example.test/hook',
        'ftp://hooks.example.test/hook',
        'https://user:pass@hooks.example.test/hook'
      ].each do |url|
        expect do
          inertia_visit(:post, '/support/admin/webhooks', form_body.merge(url: url),
                        referer: '/support/admin/webhooks/new')
        end.not_to change(Escalated::Webhook, :count), url

        expect(response).to redirect_to('/support/admin/webhooks/new')
      end
    end

    it 'refuses to move an existing webhook onto a private address' do
      webhook = create_webhook

      inertia_visit(:put, "/support/admin/webhooks/#{webhook.id}", form_body.merge(url: 'http://169.254.169.254/latest'))

      expect(webhook.reload.url).to eq(hook_url)
    end

    it 'deletes a webhook' do
      webhook = create_webhook

      expect do
        inertia_visit(:delete, "/support/admin/webhooks/#{webhook.id}")
      end.to change(Escalated::Webhook, :count).by(-1)
    end
  end

  describe 'the delivery log' do
    it 'shows each delivery with the fields the page reads' do
      webhook = create_webhook
      Escalated::WebhookDelivery.create!(webhook: webhook, event: 'ticket.created',
                                         payload: { 'ticket' => { 'id' => 7 } },
                                         response_code: 500, response_body: 'boom', attempts: 3)

      get "/support/admin/webhooks/#{webhook.id}/deliveries"

      expect(response).to have_http_status(:ok)
      page = inertia_page_from(response.body)
      expect(page['component']).to eq('Escalated/Admin/Webhooks/DeliveryLog')
      expect(page.dig('props', 'webhook', 'url')).to eq(hook_url)
      expect(page.dig('props', 'deliveries', 'data').sole).to include(
        'event' => 'ticket.created', 'response_code' => 500, 'attempts' => 3, 'payload' => { 'ticket' => { 'id' => 7 } }
      )
    end

    it 'retries a delivery' do
      webhook = create_webhook
      delivery = Escalated::WebhookDelivery.create!(webhook: webhook, event: 'ticket.created',
                                                    payload: { 'ticket' => { 'id' => 7 } },
                                                    response_code: 500, attempts: 3)
      stub = stub_request(:post, hook_url).to_return(status: 200, body: 'ok')
      log = "/support/admin/webhooks/#{webhook.id}/deliveries"

      expect do
        perform_enqueued_jobs do
          post "/support/admin/webhooks/deliveries/#{delivery.id}/retry",
               headers: { 'Referer' => "http://www.example.com#{log}" }
        end
      end.to change(Escalated::WebhookDelivery, :count).by(1)

      expect(response).to redirect_to(log)
      expect(stub).to have_been_requested.once
      expect(Escalated::WebhookDelivery.order(:id).last).to have_attributes(event: 'ticket.created', response_code: 200)
    end
  end

  describe 'deliveries when tickets change' do
    it 'delivers ticket.created to a subscribed webhook, signed with its secret' do
      webhook = create_webhook(events: ['ticket.created'], secret: 'shared-secret')
      stub_request(:post, hook_url).to_return(status: 200, body: 'ok')
      ticket = nil

      expect do
        perform_enqueued_jobs { ticket = create_ticket }
      end.to change(Escalated::WebhookDelivery, :count).by(1)

      expect(Escalated::WebhookDelivery.last).to have_attributes(webhook_id: webhook.id, event: 'ticket.created',
                                                                 response_code: 200)
      expect(
        a_request(:post, hook_url).with do |request|
          request.headers['X-Escalated-Event'] == 'ticket.created' &&
            request.headers['X-Escalated-Signature'] ==
              OpenSSL::HMAC.hexdigest('SHA256', 'shared-secret', request.body) &&
            JSON.parse(request.body).dig('payload', 'ticket', 'reference') == ticket.reference
        end
      ).to have_been_made.once
    end

    it 'delivers a reply and an internal note as their own events' do
      webhook = create_webhook(events: %w[reply.created internal_note.added])
      stub_request(:post, hook_url).to_return(status: 200)
      ticket = create_ticket
      agent = create(:user, :agent)

      perform_enqueued_jobs do
        Escalated::Services::TicketService.reply(ticket, body: 'On it.', author: agent, is_internal: false)
        Escalated::Services::TicketService.reply(ticket, body: 'Check the toner.', author: agent, is_internal: true)
      end

      expect(webhook.deliveries.order(:id).pluck(:event)).to eq(%w[reply.created internal_note.added])
    end

    it 'sends nothing to a webhook that is inactive or subscribed to something else' do
      create_webhook(events: ['ticket.created'], active: false)
      create_webhook(url: 'https://hooks.example.test/other', events: ['reply.created'])

      expect do
        perform_enqueued_jobs { create_ticket }
      end.not_to change(Escalated::WebhookDelivery, :count)
    end

    it 'keeps the query string, and posts to / when the URL has no path' do
      create_webhook(url: 'https://hooks.example.test?token=abc')
      stub = stub_request(:post, 'https://hooks.example.test/?token=abc').to_return(status: 200)

      perform_enqueued_jobs { create_ticket }

      expect(stub).to have_been_requested.once
    end

    it 'does not connect once the host resolves to a private address' do
      create_webhook
      allow(Addrinfo).to receive(:getaddrinfo).and_return([instance_double(Addrinfo, ip_address: '169.254.169.254')])

      expect do
        perform_enqueued_jobs { create_ticket }
      end.to change(Escalated::WebhookDelivery, :count).by(1)

      expect(Escalated::WebhookDelivery.last).to have_attributes(response_code: 0)
      expect(Escalated::WebhookDelivery.last.response_body).to include('private')
      expect(a_request(:any, /hooks\.example\.test/)).not_to have_been_made
    end
  end
end
