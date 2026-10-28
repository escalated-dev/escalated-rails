# frozen_string_literal: true

require 'rails_helper'

# The mobile guest API, as the canonical contract describes it
# (escalated-developer-context domain-model/mobile-guest-api.md; Laravel's
# routes/mobile-api.php is the port of record). Every example goes through the
# host app's real router at the REST API prefix plus /mobile.
RSpec.describe 'Mobile guest API', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:prefix) { '/support/api/v1/mobile/guest' }
  let(:json_headers) { { 'CONTENT_TYPE' => 'application/json', 'ACCEPT' => 'application/json' } }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:email) { 'jane@example.com' }
  let(:ticket_fields) do
    { name: 'Jane', email: email, subject: 'Order missing', description: 'It never came.' }
  end

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    # The guest throttles get their own examples below; these send many requests.
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil,
                                                       guest_rate_limit_settings: { enabled: false })
    allow(Escalated::Broadcasting).to receive(:broadcast)
    Escalated::EscalatedSetting.set('guest_tickets_enabled', '1')
    Escalated::EscalatedSetting.set('widget_enabled', '1')
    ActionMailer::Base.deliveries.clear
  end

  def post_json(path, payload, headers = {})
    post path, params: payload.to_json, headers: json_headers.merge(headers)
  end

  def mobile_proof(purpose = 'ticket', address = email)
    guest_proof(address, purpose, prefix: prefix)
  end

  def mobile_create(payload = {})
    post_json("#{prefix}/tickets", ticket_fields.merge(payload))
  end

  # A ticket made through the mobile route; returns [ticket, grant].
  def created_ticket
    mobile_create(mobile_proof)
    expect(response).to have_http_status(:created)
    data = response.parsed_body['data']
    [Escalated::Ticket.find(data['id']), data['guest_access_token']]
  end

  def expect_privacy_headers
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.headers['Cache-Control']).to include('private')
    expect(response.headers['Referrer-Policy']).to eq('no-referrer')
  end

  def upload(name = 'note.txt', type = 'text/plain', body = 'hello')
    file = Tempfile.new('upload')
    file.write(body)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, type, original_filename: name)
  end

  describe 'POST /guest/verification' do
    it 'answers 202 with the verification id and emails the code' do
      post_json("#{prefix}/verification", { email: ' Jane@Example.com ', purpose: 'ticket' })

      expect(response).to have_http_status(:accepted)
      body = response.parsed_body
      expect(body.keys).to contain_exactly('verification_id', 'expires_in', 'message')
      expect(body['expires_in']).to eq(600)
      expect(ActionMailer::Base.deliveries.last.to).to eq([email])
      expect(response.body).not_to include(last_guest_code)
      expect_privacy_headers
    end

    it 'is 403 for ticket and lookup codes while guest tickets are off' do
      Escalated::EscalatedSetting.set('guest_tickets_enabled', '0')

      post_json("#{prefix}/verification", { email: email, purpose: 'lookup' })

      expect(response).to have_http_status(:forbidden)
      expect_privacy_headers
    end
  end

  describe 'POST /guest/tickets' do
    it 'is 422 without proof and creates no contact or ticket' do
      expect { mobile_create }.not_to(change { [Escalated::Ticket.count, Escalated::Contact.count] })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 'verification_code')).to be_present
      expect_privacy_headers
    end

    it 'is 422 with a wrong code or a code for another purpose, and creates nothing' do
      proof = mobile_proof
      expect { mobile_create(proof.merge(verification_code: '00000000')) }
        .not_to(change { [Escalated::Ticket.count, Escalated::Contact.count] })
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 'verification_code')).to be_present

      expect { mobile_create(mobile_proof('lookup')) }.not_to change(Escalated::Ticket, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'is 403 while guest tickets are off, before validation' do
      Escalated::EscalatedSetting.set('guest_tickets_enabled', '0')

      post_json("#{prefix}/tickets", {})

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq('message' => 'Guest tickets are not enabled.')
    end

    it 'validates the fields before the proof' do
      post_json("#{prefix}/tickets", { email: 'nope', priority: 'whenever', verification_id: 'x',
                                       verification_code: '1' * 17, department_id: 999_999 })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['errors'].keys)
        .to include('name', 'email', 'subject', 'description', 'priority', 'department_id',
                    'verification_id', 'verification_code')
      expect(response.parsed_body['message']).to be_present
    end

    it 'creates the ticket with a grant and answers with the mobile ticket object' do
      department = create(:escalated_department)

      mobile_create(mobile_proof.merge(priority: 'high', department_id: department.id))

      expect(response).to have_http_status(:created)
      expect_privacy_headers
      expect(response.parsed_body['message']).to eq('Ticket created.')
      data = response.parsed_body['data']
      expect(data).to include(
        'subject' => 'Order missing', 'description' => 'It never came.',
        'status' => { 'value' => 'open', 'label' => 'Open' }, 'priority' => { 'value' => 'high', 'label' => 'High' },
        'channel' => 'web', 'metadata' => {}, 'requester' => { 'name' => 'Jane', 'email' => email },
        'assignee' => nil, 'department' => { 'id' => department.id, 'name' => department.name },
        'tags' => [], 'replies' => [], 'activities' => [], 'is_following' => false, 'followers_count' => 0,
        'resolved_at' => nil, 'closed_at' => nil
      )
      expect(data.keys).to include('id', 'reference', 'created_at', 'updated_at')
      expect(data['sla'].keys).to contain_exactly('first_response_due_at', 'first_response_at',
                                                  'first_response_breached', 'resolution_due_at',
                                                  'resolution_breached')
      expect(Time.zone.parse(data['guest_access_expires_at'])).to be_within(1.minute).of(24.hours.from_now)
    end

    it 'stores a verified web guest ticket, ignores privileged fields and announces it after commit' do
      announced = []
      allow(Escalated::Services::TicketService).to receive(:announce_created).and_wrap_original do |original, t|
        announced << t
        original.call(t)
      end

      mobile_create(mobile_proof.merge(email: 'JANE@example.com', status: 'closed', assigned_to: 1,
                                       metadata: { 'plan' => 'gold' }, external_reference: 'EXT-1'))

      expect(response).to have_http_status(:created)
      data = response.parsed_body['data']
      ticket = Escalated::Ticket.find(data['id'])
      expect(ticket).to have_attributes(guest_email: email, guest_name: 'Jane', guest_verified_email: email,
                                        channel: 'web', status: 'open', assigned_to: nil, metadata: {})
      expect(ticket.contact&.email).to eq(email)
      expect(Escalated::GuestAccess.resolve(data['guest_access_token'])).to eq(ticket)
      expect(announced).to eq([ticket])
    end

    it 'spends the code: using it again is 422' do
      proof = mobile_proof
      mobile_create(proof)
      expect(response).to have_http_status(:created)

      expect { mobile_create(proof) }.not_to change(Escalated::Ticket, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 'verification_code')).to be_present
    end

    it 'accepts multipart attachments and hands back grant-bound download links' do
      post "#{prefix}/tickets", params: ticket_fields.merge(mobile_proof).merge(attachments: [upload]),
                                headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:created)
      ticket = Escalated::Ticket.find(response.parsed_body.dig('data', 'id'))
      expect(ticket.attachments.map(&:filename)).to eq(['note.txt'])
    end

    it 'refuses a disallowed attachment before spending the code' do
      proof = mobile_proof
      exe = upload('x.exe', 'application/x-msdownload')
      post "#{prefix}/tickets", params: ticket_fields.merge(proof).merge(attachments: [exe]),
                                headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 'attachments')).to be_present
      expect(Escalated::Ticket.count).to eq(0)

      mobile_create(proof)
      expect(response).to have_http_status(:created)
    end

    it 'refuses more than 10 attachments' do
      post "#{prefix}/tickets", params: ticket_fields.merge(mobile_proof).merge(attachments: Array.new(11) { upload }),
                                headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 'attachments')).to be_present
    end
  end

  describe 'GET /guest/tickets/{token}' do
    it 'shows the ticket with its public replies newest first, never internal notes' do
      ticket, grant = created_ticket
      agent = create(:user, :agent, name: 'Sam Agent', email: 'sam@staff.test')
      older = create(:escalated_reply, ticket: ticket, author: agent, body: 'We are on it', created_at: 2.hours.ago)
      create(:escalated_reply, :internal, ticket: ticket, author: agent, body: 'secret staff note')
      guest_reply = create(:escalated_reply, ticket: ticket, author: nil, body: 'Any news?', created_at: 1.hour.ago)

      get "#{prefix}/tickets/#{grant}", headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:ok)
      expect_privacy_headers
      expect(response.body).not_to include('secret staff note')
      data = response.parsed_body['data']
      expect(data['guest_access_token']).to eq(grant)
      expect(data['replies'].pluck('id')).to eq([guest_reply.id, older.id])
      expect(data['replies'][0]).to include('author' => { 'id' => 0, 'name' => 'Jane', 'email' => email },
                                            'is_internal_note' => false, 'is_pinned' => false)
    end

    it 'names staff by display name only and links attachments under the grant' do
      ticket, grant = created_ticket
      agent = create(:user, :agent, name: 'Sam Agent', email: 'sam@staff.test')
      reply = create(:escalated_reply, ticket: ticket, author: agent, body: 'Invoice attached')
      pdf = upload('invoice.pdf', 'application/pdf')
      attachment = Escalated::Services::AttachmentService.attach(reply, [pdf]).first
      ticket.update_columns(assigned_to: agent.id)

      get "#{prefix}/tickets/#{grant}"

      expect(response.body).not_to include('sam@staff.test')
      data = response.parsed_body['data']
      expect(data['assignee']).to eq('id' => 0, 'name' => 'Sam Agent', 'email' => '')
      staff = data['replies'].sole
      expect(staff['author']).to eq('id' => 0, 'name' => 'Sam Agent', 'email' => '')
      expect(staff['attachments'].sole).to include('id' => attachment.id, 'filename' => 'invoice.pdf',
                                                   'mime_type' => 'application/pdf')
      url = staff['attachments'].sole['url']
      expect(url).to start_with("/support/attachments/#{attachment.id}?token=")
      get url
      expect(response).to have_http_status(:ok)
    end

    it 'shares grants with the guest page and the widget, both ways' do
      ticket, grant = created_ticket

      get "/support/widget/tickets/#{ticket.reference}",
          headers: { 'ACCEPT' => 'application/json', 'Authorization' => "Bearer #{grant}" }
      expect(response).to have_http_status(:ok)

      get "/support/guest/#{grant}"
      expect(response).to have_http_status(:ok)

      post_json('/support/widget/tickets', ticket_fields.merge(guest_proof(email)))
      expect(response).to have_http_status(:created)
      widget_reference = response.parsed_body['reference']
      widget_grant = response.parsed_body['guest_access_token']

      get "#{prefix}/tickets/#{widget_grant}"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'reference')).to eq(widget_reference)
    end

    it 'is 404 for a bad, malformed, over-long, expired, rotated or chat grant' do
      ticket, grant = created_ticket
      chat_grant = Escalated::GuestAccess.issue(ticket, email: email, purpose: 'chat')

      ['nope', 'a.b', 'A' * 5000, chat_grant].each do |token|
        get "#{prefix}/tickets/#{CGI.escape(token)}"
        expect(response).to have_http_status(:not_found)
        expect_privacy_headers
      end
      # Issuing the chat grant rotated the ticket's grant.
      get "#{prefix}/tickets/#{grant}"
      expect(response).to have_http_status(:not_found)

      fresh = Escalated::GuestAccess.issue(ticket, email: email)
      travel_to(25.hours.from_now) do
        get "#{prefix}/tickets/#{fresh}"
        expect(response).to have_http_status(:not_found)
        post_json("#{prefix}/tickets/#{fresh}/replies", { email: email, body: 'hello?' })
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /guest/lookup' do
    it 'hands out a fresh grant that works here and retires the old one' do
      ticket, grant = created_ticket

      post_json("#{prefix}/lookup", mobile_proof('lookup').merge(email: email, reference: ticket.reference))

      expect(response).to have_http_status(:ok)
      expect_privacy_headers
      entry = response.parsed_body['data'].sole
      expect(entry.keys).to contain_exactly('reference', 'subject', 'guest_access_token', 'expires_at')

      get "#{prefix}/tickets/#{entry['guest_access_token']}"
      expect(response).to have_http_status(:ok)
      get "#{prefix}/tickets/#{grant}"
      expect(response).to have_http_status(:not_found)
    end

    it 'is 422 on a bad code' do
      post_json("#{prefix}/lookup", mobile_proof('lookup').merge(email: email, reference: 'ESC-1',
                                                                 verification_code: '00000000'))

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 'verification_code')).to be_present
    end
  end

  describe 'POST /guest/tickets/{token}/replies' do
    it 'stores a public guest reply when the email matches in any case' do
      ticket, grant = created_ticket
      announced = []
      allow(Escalated::Services::NotificationService).to receive(:dispatch).and_wrap_original do |original, *args, **kw|
        announced << args.first
        original.call(*args, **kw)
      end

      post_json("#{prefix}/tickets/#{grant}/replies", { email: ' JANE@Example.COM ', body: 'Thanks' })

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to eq('message' => 'Reply sent.')
      expect_privacy_headers
      reply = ticket.replies.sole
      expect(reply).to have_attributes(body: 'Thanks', author_id: nil, is_internal: false)
      expect(announced).to include(:reply_added)
    end

    it 'is 403 when the email does not match the ticket' do
      _ticket, grant = created_ticket

      post_json("#{prefix}/tickets/#{grant}/replies", { email: 'someone@else.test', body: 'Thanks' })

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq('message' => 'The provided email does not match this ticket.')
      expect(Escalated::Reply.count).to eq(0)
    end

    it 'is 422 on a closed ticket, before validation' do
      ticket, grant = created_ticket
      ticket.update_columns(status: Escalated::Ticket.statuses[:closed])

      post_json("#{prefix}/tickets/#{grant}/replies", {})

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq('message' => 'This ticket is closed.')
    end

    it 'validates the body and email' do
      _ticket, grant = created_ticket

      post_json("#{prefix}/tickets/#{grant}/replies", { email: 'nope', body: '' })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['errors'].keys).to include('email', 'body')
    end

    it 'is 404 for a bad grant' do
      post_json("#{prefix}/tickets/not-a-grant/replies", { email: email, body: 'Thanks' })

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'rate limits' do
    around { |example| travel_to(Time.zone.parse('2026-01-01 12:00:15')) { example.run } }

    def guest_limits(**settings)
      allow(Escalated.configuration).to receive(:guest_rate_limit_settings).and_call_original
      allow(Escalated.configuration).to receive(:guest_rate_limit).and_return(settings)
    end

    it 'answers 429 with Retry-After once the per-IP guest request budget is spent' do
      guest_limits(requests_per_minute: 2)

      statuses = Array.new(3) do
        get "#{prefix}/tickets/nope", env: { 'REMOTE_ADDR' => '203.0.113.9' }
        response.status
      end

      expect(statuses).to eq([404, 404, 429])
      expect(response.headers['Retry-After'].to_i).to be_between(1, 60)
      expect_privacy_headers
    end

    it 'shares the submissions budget with the widget' do
      guest_limits(tickets_per_minute: 2)
      allow(Escalated.configuration).to receive_messages(guest_codes_per_client_per_hour: 100,
                                                         guest_codes_per_mailbox_per_hour: 100)
      ip = { 'REMOTE_ADDR' => '203.0.113.7' }

      post_json('/support/widget/verification', { email: email, purpose: 'ticket' }, ip)
      expect(response).to have_http_status(:accepted)
      post_json("#{prefix}/verification", { email: email, purpose: 'ticket' }, ip)
      expect(response).to have_http_status(:accepted)
      post_json("#{prefix}/tickets", ticket_fields, ip)

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers['Retry-After']).to be_present
    end

    it 'shares the replies budget between lookup and replies' do
      guest_limits(replies_per_minute: 1)
      ip = { 'REMOTE_ADDR' => '203.0.113.8' }

      post_json("#{prefix}/lookup", { email: email, reference: 'ESC-1' }, ip)
      expect(response).not_to have_http_status(:too_many_requests)
      post_json("#{prefix}/tickets/nope/replies", { email: email, body: 'x' }, ip)
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'counts the mobile routes against the API limiter' do
      allow(Escalated.configuration).to receive(:api_rate_limit).and_return(2)
      ip = { 'REMOTE_ADDR' => '203.0.113.10' }

      get "#{prefix}/tickets/nope", env: ip
      expect(response.headers['X-RateLimit-Limit']).to eq('2')
      expect(response.headers['X-RateLimit-Remaining']).to eq('1')
      get "#{prefix}/tickets/nope", env: ip
      get "#{prefix}/tickets/nope", env: ip

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body).to include('message' => 'Too many requests.', 'retry_after' => Integer)
      expect(response.headers['Retry-After']).to be_present
    end
  end

  describe 'while the REST API is disabled' do
    after do
      Escalated.configuration.api_enabled = true
      Rails.application.reload_routes!
    end

    it 'does not register the routes' do
      Escalated.configuration.api_enabled = false
      Rails.application.reload_routes!

      %w[verification lookup tickets].each do |path|
        expect { Rails.application.routes.recognize_path("#{prefix}/#{path}", method: :post) }
          .to raise_error(ActionController::RoutingError)
      end
      expect { Rails.application.routes.recognize_path("#{prefix}/tickets/abc", method: :get) }
        .to raise_error(ActionController::RoutingError)
      expect { Rails.application.routes.recognize_path("#{prefix}/tickets/abc/replies", method: :post) }
        .to raise_error(ActionController::RoutingError)
    end
  end
end
