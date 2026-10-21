# frozen_string_literal: true

require 'cgi'
require 'json'
require 'rails_helper'
require 'tempfile'

# Attachments are served only through the signed, expiring download route, and
# only to someone who may see them at that moment (escalated-laravel
# docs/private-attachments.md). The screens used to hand out rails_blob_path
# links, which anyone holding one could open with no ticket-access check.
RSpec.describe 'Private attachments', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:agent) { create(:user, :agent, email: 'attach-agent@example.test') }
  let(:customer) { create(:user, email: 'attach-customer@example.test') }
  let(:stranger) { create(:user, email: 'attach-stranger@example.test') }
  let(:ticket) { create(:escalated_ticket, requester: customer, guest_token: 'g' * 64) }
  let(:public_reply) { create(:escalated_reply, ticket: ticket, author: agent, is_internal: false) }
  let(:note) { create(:escalated_reply, ticket: ticket, author: agent, is_internal: true) }

  let!(:on_ticket) { attach(ticket, "..\\..\\etc/re\r\nport.svg", 'image/svg+xml', '<svg onload="alert(1)"/>') }
  let!(:on_reply) { attach(public_reply, 'invoice.pdf', 'application/pdf', '%PDF-1.4 public') }
  let!(:on_note) { attach(note, 'notes.txt', 'text/plain', 'staff only') }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    Escalated::EscalatedSetting.set('guest_tickets_enabled', '1')
  end

  def attach(parent, name, type, body)
    file = Tempfile.new('upload')
    file.write(body)
    file.rewind
    upload = Rack::Test::UploadedFile.new(file.path, type, original_filename: name)
    Escalated::Services::AttachmentService.attach(parent, [upload]).first
  end

  def sign_in_as(user)
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)
  end

  def page_props(path)
    get path
    expect(response).to have_http_status(:ok)
    JSON.parse(CGI.unescapeHTML(response.body[%r{data-page="(.+?)"></div>}m, 1]))['props']
  end

  def link(attachment, guest_ticket: nil)
    Escalated::AttachmentAccess.url(attachment, guest_ticket: guest_ticket)
  end

  describe 'links on the screens' do
    it 'points every attachment at the signed download route, never at storage' do
      note
      sign_in_as(agent)

      body = page_props("/support/agent/tickets/#{ticket.reference}").to_json

      expect(body).not_to include('rails/active_storage')
      urls = body.scan(%r{/support/attachments/\d+\?token=[^"\\]+})
      expect(urls.size).to be >= 3
    end

    it 'gives API clients the same route' do
      public_reply
      token = Escalated::ApiToken.create_token(agent, 'test')[:plain_text_token]

      get "/support/api/v1/tickets/#{ticket.reference}", headers: { 'Authorization' => "Bearer #{token}" }

      url = response.parsed_body.dig('data', 'replies', 0, 'attachments', 0, 'url')
      expect(url).to start_with("/support/attachments/#{on_reply.id}?token=")
    end
  end

  describe 'downloading' do
    it 'sends an agent the file as a private, non-sniffable download with a safe name' do
      sign_in_as(agent)

      get link(on_ticket)

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('<svg onload="alert(1)"/>')
      expect(response.headers['Content-Type']).to eq('application/octet-stream')
      expect(response.headers['Content-Disposition']).to start_with('attachment;')
      expect(response.headers['Content-Disposition']).to include('filename="report.svg"')
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
      expect(response.headers['Cache-Control']).to include('private', 'no-store')
    end

    it 'keeps a safe type such as a PDF, still as an attachment' do
      sign_in_as(agent)

      get link(on_reply)

      expect(response.headers['Content-Type']).to eq('application/pdf')
      expect(response.headers['Content-Disposition']).to start_with('attachment;')
    end

    it 'refuses a missing, forged, swapped or expired link' do
      sign_in_as(agent)

      get "/support/attachments/#{on_ticket.id}"
      expect(response).to have_http_status(:not_found)

      get "/support/attachments/#{on_ticket.id}?token=forged"
      expect(response).to have_http_status(:not_found)

      get link(on_reply).sub("/attachments/#{on_reply.id}?", "/attachments/#{on_note.id}?")
      expect(response).to have_http_status(:not_found)

      url = link(on_ticket)
      travel 11.minutes do
        get url
        expect(response).to have_http_status(:not_found)
      end
    end

    it 'lets the requester download public files but not internal-note files' do
      sign_in_as(customer)

      get link(on_ticket)
      expect(response).to have_http_status(:ok)
      get link(on_reply)
      expect(response).to have_http_status(:ok)
      get link(on_note)
      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses a signed-in user who cannot see the ticket, and a visitor with no session' do
      url = link(on_ticket)

      get url
      expect(response).to have_http_status(:forbidden)

      sign_in_as(stranger)
      get url
      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses an agent outside the ticket department under department visibility' do
      allow(Escalated.configuration).to receive(:visibility).and_return('department')
      ticket.update!(department: create(:escalated_department))
      create(:escalated_department).agents << agent
      sign_in_as(agent)

      get link(on_ticket)

      expect(response).to have_http_status(:forbidden)
    end

    it 'accepts an API bearer token and never falls back to the session for a bad one' do
      token = Escalated::ApiToken.create_token(agent, 'test')[:plain_text_token]
      url = link(on_note)

      get url, headers: { 'Authorization' => "Bearer #{token}" }
      expect(response).to have_http_status(:ok)

      sign_in_as(agent)
      get url, headers: { 'Authorization' => 'Bearer not-a-token' }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'guests' do
    it 'downloads with the link the guest page rendered, until the guest token changes' do
      public_reply
      props = page_props("/support/guest/#{ticket.guest_token}")
      url = props.dig('ticket', 'attachments', 0, 'url')
      reply_url = props.dig('replies', 0, 'attachments', 0, 'url')

      get url
      expect(response).to have_http_status(:ok)
      get reply_url
      expect(response).to have_http_status(:ok)

      ticket.update!(guest_token: 'h' * 64)
      get url
      expect(response).to have_http_status(:forbidden)
    end

    it 'never gets an internal-note file' do
      get link(on_note, guest_ticket: ticket)

      expect(response).to have_http_status(:forbidden)
    end

    it 'cannot use a capability for one ticket on another ticket' do
      other = create(:escalated_ticket, guest_token: 'o' * 64)

      get link(on_ticket, guest_ticket: other)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
