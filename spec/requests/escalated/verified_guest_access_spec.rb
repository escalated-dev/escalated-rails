# frozen_string_literal: true

require 'cgi'
require 'json'
require 'rails_helper'

# Verified guest access, as escalated-laravel docs/guest-access.md describes
# it and the shared frontend drives it (pages/Guest/Create.vue,
# widget/EscalatedWidget.vue, composables/useGuestVerification.js).
RSpec.describe 'Verified guest access', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:json_headers) { { 'CONTENT_TYPE' => 'application/json', 'ACCEPT' => 'application/json' } }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:email) { 'jane@example.com' }

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    # The per-IP guest throttles have their own specs; these send many requests.
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil,
                                                       guest_rate_limit_settings: { enabled: false })
    allow(Escalated::Broadcasting).to receive(:broadcast)
    Escalated::EscalatedSetting.set('widget_enabled', '1')
    ActionMailer::Base.deliveries.clear
  end

  def post_json(path, payload, headers = {})
    post path, params: payload.to_json, headers: json_headers.merge(headers)
  end

  # An Inertia visit gets the page as JSON, a plain visit as HTML.
  def inertia_props
    return response.parsed_body['props'] if response.media_type == 'application/json'

    JSON.parse(CGI.unescapeHTML(response.body[%r{data-page="(.+?)"></div>}m, 1]))['props']
  end

  def widget_ticket(payload = {})
    post_json('/support/widget/tickets',
              { name: 'Jane', email: email, subject: 'Order missing', description: 'It never came.' }.merge(payload))
  end

  def widget_status(reference, grant)
    get "/support/widget/tickets/#{reference}",
        headers: { 'ACCEPT' => 'application/json', 'Authorization' => "Bearer #{grant}" }
  end

  describe 'POST verification' do
    it 'emails an 8-digit code and answers 202 with only the verification id' do
      post_json('/support/widget/verification', { email: ' Jane@Example.com ', purpose: 'ticket' })

      expect(response).to have_http_status(:accepted)
      body = response.parsed_body
      expect(body['verification_id']).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
      expect(body['expires_in']).to eq(600)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([email])
      expect(last_guest_code).to match(/\A\d{8}\z/)
      expect(response.body).not_to include(last_guest_code)
      expect(response.headers['Cache-Control']).to include('no-store')
    end

    it 'is offered under the guest prefix too' do
      post_json('/support/guest/verification', { email: email, purpose: 'lookup' })

      expect(response).to have_http_status(:accepted)
    end

    it 'refuses a bad email or purpose, and chat while chat is off' do
      post_json('/support/widget/verification', { email: 'not-an-email', purpose: 'ticket' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 'email')).to be_present

      post_json('/support/widget/verification', { email: email, purpose: 'admin' })
      expect(response).to have_http_status(:unprocessable_content)

      Escalated::EscalatedSetting.set('chat_enabled', '0')
      post_json('/support/widget/verification', { email: email, purpose: 'chat' })
      expect(response).to have_http_status(:forbidden)
    end

    it 'sends a mailbox 3 codes an hour per client and 10 across clients' do
      3.times { post_json('/support/widget/verification', { email: email, purpose: 'ticket' }) }
      expect(response).to have_http_status(:accepted)

      post_json('/support/widget/verification', { email: email, purpose: 'ticket' })
      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers['Retry-After'].to_i).to be_between(1, 3600)

      statuses = (1..8).map do |n|
        post_json('/support/widget/verification', { email: email, purpose: 'ticket' }, 'REMOTE_ADDR' => "10.1.0.#{n}")
        response.status
      end
      expect(statuses).to eq(([202] * 7) + [429])
      expect(ActionMailer::Base.deliveries.size).to eq(10)
    end
  end

  describe 'widget tickets' do
    it 'advertises verification and the status lookup in /config' do
      get '/support/widget/config', headers: { 'ACCEPT' => 'application/json' }

      expect(response.parsed_body).to include('guest_verification_required' => true, 'status_lookup_enabled' => true)
    end

    it 'refuses a ticket without proof' do
      expect { widget_ticket }.not_to change(Escalated::Ticket, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 'verification_code')).to be_present
    end

    it 'creates the ticket with proof and answers with an expiring grant instead of a guest token' do
      proof = guest_proof(email)
      announced = []
      allow(Escalated::Services::TicketService).to receive(:announce_created).and_wrap_original do |original, t|
        announced << t
        original.call(t)
      end

      widget_ticket(proof)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body).not_to have_key('guest_token')
      expect(body['guest_access_token']).to be_present
      expect(Time.zone.parse(body['expires_at'])).to be_within(1.minute).of(24.hours.from_now)
      ticket = Escalated::Ticket.find_by!(reference: body['reference'])
      expect(ticket).to have_attributes(guest_token: nil, guest_email: email, guest_verified_email: email)
      expect(ticket.guest_access_hash).not_to include(body['guest_access_token'])
      expect(announced).to eq([ticket])
    end

    it 'counts a wrong code, allows five guesses and uses a code once' do
      proof = guest_proof(email)

      5.times { widget_ticket(proof.merge(verification_code: '00000000')) }
      widget_ticket(proof)
      expect(response).to have_http_status(:unprocessable_content)
      expect(Escalated::Ticket.count).to eq(0)

      fresh = guest_proof(email)
      widget_ticket(fresh)
      expect(response).to have_http_status(:created)
      widget_ticket(fresh)
      expect(response).to have_http_status(:unprocessable_content)
      expect(Escalated::Ticket.count).to eq(1)
    end

    it 'refuses a proof for another email, another purpose, or after ten minutes' do
      widget_ticket(guest_proof('other@example.com'))
      expect(response).to have_http_status(:unprocessable_content)

      widget_ticket(guest_proof(email, 'lookup'))
      expect(response).to have_http_status(:unprocessable_content)

      proof = guest_proof(email)
      travel 11.minutes do
        widget_ticket(proof)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it 'shows the status only for the grant and its own reference' do
      widget_ticket(guest_proof(email))
      reference = response.parsed_body['reference']
      grant = response.parsed_body['guest_access_token']
      ticket = Escalated::Ticket.find_by!(reference: reference)
      create(:escalated_reply, ticket: ticket, body: 'We are looking.', is_internal: false)
      create(:escalated_reply, ticket: ticket, body: 'Secret note.', is_internal: true)

      widget_status(reference, grant)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('reference' => reference, 'subject' => 'Order missing')
      expect(response.parsed_body['replies'].pluck('body')).to eq(['We are looking.'])
      expect(response.headers['Cache-Control']).to include('no-store')

      other = create(:escalated_ticket)
      widget_status(other.reference, grant)
      expect(response).to have_http_status(:not_found)

      get "/support/widget/tickets/#{reference}?email=#{email}", headers: { 'ACCEPT' => 'application/json' }
      expect(response).to have_http_status(:not_found)

      travel 25.hours do
        widget_status(reference, grant)
        expect(response).to have_http_status(:not_found)
      end
    end

    it 'finds the guest tickets by reference and verified email, and rotates the grant' do
      widget_ticket(guest_proof(email))
      reference = response.parsed_body['reference']
      first_grant = response.parsed_body['guest_access_token']

      post_json('/support/widget/lookup', { email: email, reference: reference }.merge(guest_proof(email, 'lookup')))

      expect(response).to have_http_status(:ok)
      match = response.parsed_body['data'].sole
      expect(match).to include('reference' => reference, 'subject' => 'Order missing')
      expect(match['expires_at']).to be_present

      widget_status(reference, match['guest_access_token'])
      expect(response).to have_http_status(:ok)
      widget_status(reference, first_grant)
      expect(response).to have_http_status(:not_found)
    end

    it 'finds nothing for a reference with someone else email, and still uses the code' do
      ticket = create(:escalated_ticket, guest_email: 'owner@example.com')
      proof = guest_proof(email, 'lookup')

      post_json('/support/widget/lookup', { email: email, reference: ticket.reference }.merge(proof))
      expect(response.parsed_body['data']).to eq([])

      post_json('/support/widget/lookup', { email: email, reference: ticket.reference }.merge(proof))
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'finds an older ticket (inbound email, legacy guest) and retires its permanent token' do
      legacy = create(:escalated_ticket, guest_email: 'Jane@Example.com', guest_token: 'a' * 64)

      proof = guest_proof(email, 'lookup')
      post_json('/support/widget/lookup', { email: email, reference: legacy.reference }.merge(proof))

      expect(response.parsed_body['data'].sole['reference']).to eq(legacy.reference)
      expect(legacy.reload.guest_token).to be_nil
    end

    it 'still shows a legacy ticket by its permanent token while those are accepted' do
      legacy = create(:escalated_ticket, guest_email: email, guest_token: 'b' * 64)

      get "/support/widget/tickets/#{legacy.guest_token}", headers: { 'ACCEPT' => 'application/json' }
      expect(response).to have_http_status(:ok)

      allow(Escalated.configuration).to receive(:accept_legacy_guest_tokens).and_return(false)
      get "/support/widget/tickets/#{legacy.guest_token}", headers: { 'ACCEPT' => 'application/json' }
      expect(response).to have_http_status(:not_found)
    end

    it 'needs chat proof to start a chat' do
      start = { name: 'Jane', email: email, message: 'Hi' }

      post_json('/support/widget/chat/start', start)
      expect(response).to have_http_status(:unprocessable_content)
      expect(Escalated::Ticket.count).to eq(0)

      post_json('/support/widget/chat/start', start.merge(guest_proof(email, 'chat')))
      expect(response).to have_http_status(:created)
      expect(response.parsed_body).not_to have_key('guest_token')
    end
  end

  describe 'guest pages' do
    let(:form) do
      { guest_name: 'Jane', guest_email: email, subject: 'Printer', description: 'It is on fire.', priority: 'high' }
    end

    it 'hands Guest/Create the verification and lookup URLs' do
      get '/support/guest/create'

      expect(inertia_props).to include('verification_url' => '/support/guest/verification',
                                       'lookup_url' => '/support/guest/lookup')
    end

    it 'creates the ticket from the form the page posts and redirects under the grant' do
      proof = guest_proof(email, 'ticket', prefix: '/support/guest')

      post '/support/guest', params: form.merge(proof).to_json,
                             headers: json_headers.merge('X-Inertia' => 'true')

      ticket = Escalated::Ticket.find_by!(subject: 'Printer')
      expect(ticket).to have_attributes(guest_name: 'Jane', guest_email: email, guest_token: nil)
      grant = response.location[%r{/support/guest/(.+)\z}, 1]
      expect(Escalated::GuestAccess.resolve(grant)).to eq(ticket)

      get "/support/guest/#{grant}"
      expect(response).to have_http_status(:ok)
      expect(response.headers['Referrer-Policy']).to eq('no-referrer')
      expect(inertia_props.dig('ticket', 'reference')).to eq(ticket.reference)
    end

    it 'refuses the form without proof' do
      expect do
        post '/support/guest', params: form.to_json, headers: json_headers.merge('X-Inertia' => 'true')
      end.not_to change(Escalated::Ticket, :count)

      expect(inertia_props.dig('errors', 'verification_code')).to be_present
    end

    it 'answers lookups under the guest prefix with links the page can open' do
      ticket = create(:escalated_ticket, guest_email: email)

      proof = guest_proof(email, 'lookup', prefix: '/support/guest')
      post_json('/support/guest/lookup', { email: email, reference: ticket.reference }.merge(proof))

      grant = response.parsed_body['data'].sole['guest_access_token']
      get "/support/guest/#{grant}"
      expect(response).to have_http_status(:ok)
    end

    it 'stops honouring a grant once the guest email changes' do
      widget_ticket(guest_proof(email))
      grant = response.parsed_body['guest_access_token']
      ticket = Escalated::Ticket.find_by!(reference: response.parsed_body['reference'])

      get "/support/guest/#{grant}"
      expect(response).to have_http_status(:ok)

      ticket.update!(guest_email: 'someone-else@example.com')
      get "/support/guest/#{grant}"
      expect(response).to have_http_status(:not_found)
    end

    it 'gives the guest page attachment links that die with the grant' do
      widget_ticket(guest_proof(email))
      grant = response.parsed_body['guest_access_token']
      ticket = Escalated::Ticket.find_by!(reference: response.parsed_body['reference'])
      file = Rack::Test::UploadedFile.new(StringIO.new('receipt'), 'application/pdf', original_filename: 'r.pdf')
      Escalated::Services::AttachmentService.attach(ticket, [file])

      get "/support/guest/#{grant}"
      url = inertia_props.dig('ticket', 'attachments', 0, 'url')
      get url
      expect(response).to have_http_status(:ok)

      Escalated::GuestAccess.issue(ticket.reload, email: email)
      get url
      expect(response).to have_http_status(:forbidden)
    end

    it 'never accepts a forged or truncated grant' do
      widget_ticket(guest_proof(email))
      grant = response.parsed_body['guest_access_token']

      get "/support/guest/#{grant[0..-3]}"
      expect(response).to have_http_status(:not_found)
      get "/support/guest/#{grant.reverse}"
      expect(response).to have_http_status(:not_found)
    end
  end
end
