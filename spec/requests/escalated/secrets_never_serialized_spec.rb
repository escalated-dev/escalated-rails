# frozen_string_literal: true

require 'rails_helper'

# Stored secrets never reach the browser.
#
# Import source credentials, webhook signing secrets, SSO and inbound email
# secrets, TOTP seeds, recovery codes and API token hashes are kept server-side
# so the app can use them. None of them is shown back to an admin: every page
# and JSON response that carries one of these records is checked here for the
# raw secret anywhere in the body. Mirrors escalated-laravel's
# SecretsNeverSerializedTest.
RSpec.describe 'Stored secrets are never serialized', type: :request do
  include ActiveJob::TestHelper

  let(:import_token) { FakeImportAdapter::TOKEN }
  let(:import_subdomain) { 'imp-sub-7f3a9c2e5b1d' }
  let(:webhook_secret) { 'whsec-4c8e1a7b9d3f' }
  let(:jwt_secret) { 'jwt-secret-5e6f7a8b9c' }

  let(:admin) { create(:user, :admin, email: 'admin-secrets@example.test') }
  let(:adapter) { FakeImportAdapter.new }
  let(:filter) { ->(adapters) { adapters + [adapter] } }
  let(:import_credentials) { { 'subdomain' => import_subdomain, 'api_token' => import_token } }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(admin)
    allow(Addrinfo).to receive(:getaddrinfo).and_return([instance_double(Addrinfo, ip_address: '93.184.215.14')])
    Escalated.hooks.add_filter('import.adapters', filter)
  end

  after do
    Escalated.hooks.remove_filter('import.adapters', filter)
    clear_enqueued_jobs
  end

  def expect_no_secrets(*secrets)
    expect(response).to have_http_status(:ok)
    secrets.each { |secret| expect(response.body).not_to include(secret) }
  end

  def import_job
    Escalated::ImportJob.create!(
      platform: 'fakedesk', status: 'importing', credentials: import_credentials,
      progress: { 'tickets' => { 'total' => 10, 'processed' => 4, 'skipped' => 0, 'failed' => 0, 'cursor' => nil } }
    )
  end

  def webhook
    @webhook ||= Escalated::Webhook.create!(
      url: 'https://hooks.example.test/escalated', events: ['ticket.created'], secret: webhook_secret, active: true
    )
  end

  def set_setting(key, value)
    Escalated::EscalatedSetting.set(key, value)
  end

  describe 'import jobs' do
    it 'keeps credentials out of the index, progress and status responses' do
      job = import_job

      get '/support/admin/import'
      expect_no_secrets(import_token, import_subdomain)
      expect(inertia_page.dig('props', 'jobs').sole).to include('id' => job.id, 'platform' => 'fakedesk')
      expect(inertia_page.dig('props', 'jobs').sole).not_to have_key('credentials')

      get "/support/admin/import/progress/#{job.id}"
      expect_no_secrets(import_token, import_subdomain)
      expect(inertia_page.dig('props', 'job')).to include('id' => job.id, 'status' => 'importing')
      expect(inertia_page.dig('props', 'job', 'progress', 'tickets', 'processed')).to eq(4)
      expect(inertia_page.dig('props', 'job')).not_to have_key('credentials')

      get "/support/admin/imports/#{job.id}"
      expect_no_secrets(import_token, import_subdomain)

      get "/support/admin/import/status/#{job.id}", as: :json
      expect_no_secrets(import_token, import_subdomain)
      expect(response.parsed_body['status']).to eq('importing')
    end

    it 'sends the progress page at most the last 50 errors' do
      job = import_job
      log = Array.new(60) { |i| { 'entity_type' => 'tickets', 'source_id' => "s#{i}", 'error' => 'x' } }
      job.update!(error_log: log)

      get "/support/admin/import/progress/#{job.id}"

      log = inertia_page.dig('props', 'job', 'error_log')
      expect(log.size).to eq(50)
      expect(log.last['source_id']).to eq('s59')
    end

    it 'keeps credentials out of the connect, test-connection, mapping and review steps' do
      get '/support/admin/import/fakedesk/connect'
      expect_no_secrets(import_token, import_subdomain)

      post '/support/admin/import/fakedesk/test-connection', params: { credentials: import_credentials }, as: :json
      expect_no_secrets(import_token, import_subdomain)
      expect(response.parsed_body).to eq('success' => true)

      get '/support/admin/import/fakedesk/mapping'
      expect_no_secrets(import_token, import_subdomain)

      inertia_visit(:post, '/support/admin/import/fakedesk/review', { entity_types: ['tickets'] })
      expect_no_secrets(import_token, import_subdomain)
    end

    it 'still hands the stored credentials to the import run server-side, and never serializes them' do
      job = Escalated::ImportJob.find(import_job.id)

      expect(job.credentials).to eq(import_credentials)
      expect(job.as_json).not_to have_key('credentials')
      expect(job.serializable_hash).not_to have_key('credentials')
      expect(job.to_json).not_to include(import_token)
    end
  end

  describe 'webhooks' do
    it 'keeps the signing secret out of the index, edit and delivery-log pages and reports has_secret' do
      Escalated::WebhookDelivery.create!(webhook: webhook, event: 'ticket.created', payload: { 'ok' => true },
                                         response_code: 200, attempts: 1)

      get '/support/admin/webhooks'
      expect_no_secrets(webhook_secret)
      expect(inertia_page.dig('props', 'webhooks', 0, 'has_secret')).to be(true)

      get "/support/admin/webhooks/#{webhook.id}/edit"
      expect_no_secrets(webhook_secret)
      expect(inertia_page.dig('props', 'webhook')).to include('has_secret' => true,
                                                              'url' => 'https://hooks.example.test/escalated')

      get "/support/admin/webhooks/#{webhook.id}/deliveries"
      expect_no_secrets(webhook_secret)
    end

    it 'keeps the stored secret when the form is saved with the secret left blank' do
      inertia_visit(:put, "/support/admin/webhooks/#{webhook.id}",
                    { url: webhook.url, events: %w[ticket.created ticket.updated], secret: '',
                      clear_secret: false, active: true })

      expect(response).to be_redirect
      expect(webhook.reload.secret).to eq(webhook_secret)
      expect(webhook.events).to eq(%w[ticket.created ticket.updated])
    end

    it 'keeps the stored secret when the form leaves the secret out' do
      inertia_visit(:put, "/support/admin/webhooks/#{webhook.id}", { url: webhook.url, events: ['ticket.created'] })

      expect(webhook.reload.secret).to eq(webhook_secret)
    end

    it 'replaces the secret when a new one is entered, and clears it on request' do
      body = { url: webhook.url, events: ['ticket.created'], active: true }

      inertia_visit(:put, "/support/admin/webhooks/#{webhook.id}", body.merge(secret: 'whsec-new'))
      expect(webhook.reload.secret).to eq('whsec-new')

      inertia_visit(:put, "/support/admin/webhooks/#{webhook.id}", body.merge(secret: '', clear_secret: true))
      expect(webhook.reload.secret).to be_nil

      get '/support/admin/webhooks'
      expect(inertia_page.dig('props', 'webhooks', 0, 'has_secret')).to be(false)
    end

    it 'does not serialize the secret from the model' do
      expect(webhook.as_json).not_to have_key('secret')
      expect(webhook.as_json).to include('has_secret' => true)
      expect(webhook.to_json).not_to include(webhook_secret)
    end
  end

  describe 'SSO settings' do
    it 'shows the JWT secret as the full mask, and an empty string when unset' do
      get '/support/admin/settings/sso'
      expect(inertia_page.dig('props', 'settings', 'sso_jwt_secret')).to eq('')

      set_setting('sso_provider', 'jwt')
      set_setting('sso_jwt_secret', jwt_secret)

      get '/support/admin/settings/sso'
      expect_no_secrets(jwt_secret, 'jwt-')
      expect(inertia_page.dig('props', 'settings', 'sso_jwt_secret')).to eq('********')
    end

    it 'keeps the stored secret when the mask is posted back, and replaces it with a new value' do
      set_setting('sso_jwt_secret', jwt_secret)
      get '/support/admin/settings/sso'
      settings = inertia_page.dig('props', 'settings')

      inertia_visit(:post, '/support/admin/settings/sso', settings.merge('sso_provider' => 'jwt'))
      expect(response).to be_redirect
      expect(Escalated::EscalatedSetting.get('sso_jwt_secret')).to eq(jwt_secret)
      expect(Escalated::EscalatedSetting.get('sso_provider')).to eq('jwt')

      inertia_visit(:post, '/support/admin/settings/sso', settings.merge('sso_jwt_secret' => 'jwt***********'))
      expect(Escalated::EscalatedSetting.get('sso_jwt_secret')).to eq(jwt_secret)

      inertia_visit(:post, '/support/admin/settings/sso', settings.merge('sso_jwt_secret' => 'jwt-secret-rotated'))
      expect(Escalated::EscalatedSetting.get('sso_jwt_secret')).to eq('jwt-secret-rotated')
    end
  end

  describe 'general settings' do
    it 'does not reveal any characters of the inbound email secrets' do
      set_setting('mailgun_signing_key', 'mgk-9d8c7b6a5f4e')
      set_setting('postmark_inbound_token', 'pmt-1a2b3c4d5e6f')
      set_setting('imap_password', 'imp-8f7e6d5c4b')

      get '/support/admin/settings'

      expect_no_secrets('mgk-9d8c7b6a5f4e', 'pmt-1a2b3c4d5e6f', 'imp-8f7e6d5c4b', 'mgk', 'pmt', 'imp-')
      settings = inertia_page.dig('props', 'settings')
      expect(settings.values_at('mailgun_signing_key', 'postmark_inbound_token', 'imap_password'))
        .to eq(%w[******** ******** ********])
    end

    it 'keeps the stored secrets when the full mask is posted back' do
      set_setting('imap_password', 'imp-8f7e6d5c4b')

      inertia_visit(:post, '/support/admin/settings', { imap_password: '********', imap_host: 'imap.example.test' })

      expect(Escalated::EscalatedSetting.get('imap_password')).to eq('imp-8f7e6d5c4b')
      expect(Escalated::EscalatedSetting.get('imap_host')).to eq('imap.example.test')
    end
  end

  describe 'two-factor records and API tokens' do
    let(:totp_secret) { 'TOTPSECRETBASE32XXYYZZ' }
    let(:recovery_code) { 'rc-aaaa-bbbb-cccc' }

    it 'keeps the TOTP secret and recovery codes off the two-factor page' do
      Escalated::TwoFactor.create!(user_id: admin.id, secret: totp_secret, recovery_codes: [recovery_code],
                                   confirmed_at: Time.current)

      get '/support/admin/settings/two_factor'

      expect_no_secrets(totp_secret, recovery_code)
      expect(inertia_page.dig('props', 'enabled')).to be(true)
    end

    it 'keeps the token hash off the API token page, and shows the plain token only once on creation' do
      result = Escalated::ApiToken.create_token(admin, 'CI')
      hash = result[:token].token

      get '/support/admin/api_tokens'
      expect_no_secrets(hash, result[:plain_text_token])
      expect(inertia_page.dig('props', 'tokens').sole['name']).to eq('CI')

      post '/support/admin/api_tokens', params: { user_id: admin.id, name: 'Deploy' }
      created = Escalated::ApiToken.find_by(name: 'Deploy')
      plain = flash[:plain_text_token]
      expect(Digest::SHA256.hexdigest(plain)).to eq(created.token)

      get '/support/admin/api_tokens'
      expect_no_secrets(created.token, hash)
    end

    it 'hides the secrets from model serialization' do
      two_factor = Escalated::TwoFactor.create!(user_id: admin.id, secret: totp_secret,
                                                recovery_codes: [recovery_code])
      token = Escalated::ApiToken.create_token(admin, 'CI')[:token]

      expect(two_factor.as_json.keys).not_to include('secret', 'recovery_codes')
      expect(two_factor.to_json).not_to include(totp_secret)
      expect(token.as_json).not_to have_key('token')
      expect(token.to_json).not_to include(token.token)
    end
  end
end
