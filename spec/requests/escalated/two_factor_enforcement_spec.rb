# frozen_string_literal: true

require 'rails_helper'
require 'cgi'
require 'rotp'

# ADR 2026-10-29-configurable-access-features: two-factor is an install-level
# switch (config.access[:two_factor] / ESCALATED_TWO_FACTOR). Off, enrolment and
# challenge routes answer 404 and nobody is challenged. On, a staff user with a
# confirmed enrolment must pass Auth/TwoFactorChallenge in their session before
# any admin or agent route, and admins can require everyone to enrol.
RSpec.describe 'Two-factor enforcement', type: :request do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:challenge) { '/support/two-factor/challenge' }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    Escalated.configuration.two_factor = { cache_store: cache }
  end

  after do
    Escalated.configuration.access = {}
    Escalated.configuration.two_factor = {}
  end

  def turn_on!
    Escalated.configuration.access = { two_factor: true }
  end

  def sign_in_as(user)
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)
  end

  def enrol(user, recovery = %w[AAAA1111-BBBB2222 CCCC3333-DDDD4444])
    secret = ROTP::Base32.random(20)
    Escalated::TwoFactor.create!(user_id: user.id, secret: secret, recovery_codes: recovery, confirmed_at: Time.current)
    secret
  end

  def code(secret, offset = 0)
    ROTP::TOTP.new(secret).at(Time.now.to_i + (offset * 30))
  end

  def page
    JSON.parse(CGI.unescapeHTML(response.body[%r{data-page="(.+?)"></div>}m, 1]))
  end

  describe 'switched off (the default)' do
    it 'does not challenge an enrolled user and hides the two-factor routes' do
      user = create(:user, :admin)
      enrol(user)
      sign_in_as(user)

      get '/support/agent'
      expect(response).to have_http_status(:ok)
      get '/support/admin/settings/two_factor'
      expect(response).to have_http_status(:not_found)
      post '/support/admin/settings/two_factor/setup'
      expect(response).to have_http_status(:not_found)
      get challenge
      expect(response).to have_http_status(:not_found)
      post challenge, params: { code: '000000' }
      expect(response).to have_http_status(:not_found)
    end

    it 'shares the switch off and ignores the requirement' do
      Escalated::EscalatedSetting.set('two_factor_required', '1')
      sign_in_as(create(:user, :agent))
      get '/support/agent'
      expect(response).to have_http_status(:ok)
      expect(page.dig('props', 'escalated', 'features', 'two_factor')).to be(false)
      expect(page.dig('props', 'escalated', 'two_factor_required')).to be(false)
    end

    it 'cannot be turned on from the settings store' do
      %w[two_factor access.two_factor ESCALATED_TWO_FACTOR].each { |key| Escalated::EscalatedSetting.set(key, '1') }
      user = create(:user, :agent)
      enrol(user)
      sign_in_as(user)
      get '/support/agent'
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'switched on' do
    before { turn_on! }

    it 'sends an enrolled user to the challenge from agent and admin pages' do
      user = create(:user, :admin)
      enrol(user)
      sign_in_as(user)

      get '/support/agent'
      expect(response).to redirect_to(challenge)
      get '/support/admin/departments'
      expect(response).to redirect_to(challenge)
      get '/support/agent/tickets', as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to include('two_factor_required' => true)
    end

    it 'renders the shared challenge page with the action to post to' do
      user = create(:user, :agent)
      enrol(user)
      sign_in_as(user)
      get challenge
      expect(response).to have_http_status(:ok)
      expect(page['component']).to eq('Escalated/Auth/TwoFactorChallenge')
      expect(page.dig('props', 'action')).to eq("http://www.example.com#{challenge}")
      expect(page['props']).to have_key('error')
    end

    it 'accepts a valid code and returns to the page asked for' do
      user = create(:user, :agent)
      secret = enrol(user)
      ticket = create(:escalated_ticket)
      sign_in_as(user)

      get "/support/agent/tickets/#{ticket.id}"
      expect(response).to redirect_to(challenge)
      post challenge, params: { code: code(secret) }
      expect(response).to redirect_to("/support/agent/tickets/#{ticket.id}")
      get "/support/agent/tickets/#{ticket.id}"
      expect(response).to have_http_status(:ok)
    end

    it 'refuses a wrong code with a code error' do
      user = create(:user, :agent)
      secret = enrol(user)
      sign_in_as(user)
      wrong = ((code(secret).to_i + 1) % 1_000_000).to_s.rjust(6, '0')

      post challenge, params: { code: wrong }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['errors']).to eq('code' => 'That code is not valid.')
      get '/support/agent'
      expect(response).to redirect_to(challenge)
    end

    it 'refuses a code that was already used, in a new session' do
      user = create(:user, :agent)
      secret = enrol(user)
      once = code(secret)
      sign_in_as(user)

      post challenge, params: { code: once }
      expect(response).to have_http_status(:see_other)

      reset! # a new login: a new browser session
      sign_in_as(user)
      post challenge, params: { code: once }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['errors']).to have_key('code')
    end

    it 'accepts a recovery code once' do
      user = create(:user, :agent)
      enrol(user)
      sign_in_as(user)

      post challenge, params: { recovery_code: 'aaaa1111-bbbb2222' }
      expect(response).to have_http_status(:see_other)
      get '/support/agent'
      expect(response).to have_http_status(:ok)

      reset!
      sign_in_as(user)
      post challenge, params: { recovery_code: 'AAAA1111-BBBB2222' }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['errors']).to have_key('recovery_code')
      expect(Escalated::TwoFactor.find_by(user_id: user.id).recovery_codes).to eq(%w[CCCC3333-DDDD4444])
    end

    it 'throttles the verify route' do
      user = create(:user, :agent)
      enrol(user)
      sign_in_as(user)
      5.times { post challenge, params: { code: '000000' }, as: :json }
      post challenge, params: { code: '000000' }, as: :json
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'challenges again in a new session (a new login)' do
      user = create(:user, :agent)
      secret = enrol(user)
      sign_in_as(user)
      post challenge, params: { code: code(secret) }
      get '/support/agent'
      expect(response).to have_http_status(:ok)

      reset!
      sign_in_as(user)
      get '/support/agent'
      expect(response).to redirect_to(challenge)
    end

    it 'does not pass a session for one user on to another' do
      first = create(:user, :agent)
      secret = enrol(first)
      second = create(:user, :agent)
      enrol(second)
      sign_in_as(first)
      post challenge, params: { code: code(secret) }

      sign_in_as(second)
      get '/support/agent'
      expect(response).to redirect_to(challenge)
    end

    it 'does not let an unchallenged session switch two-factor off' do
      user = create(:user, :agent)
      enrol(user)
      sign_in_as(user)
      post '/support/admin/settings/two_factor/disable'
      expect(response).to redirect_to(challenge)
      expect(Escalated::TwoFactor.where(user_id: user.id)).to exist
    end

    it 'lets an agent who is not an admin enrol, with the secret sealed at rest' do
      agent = create(:user, :agent)
      sign_in_as(agent)

      get '/support/admin/settings/two_factor'
      expect(response).to have_http_status(:ok)
      expect(page['component']).to eq('Escalated/Admin/Settings/TwoFactor')
      expect(page['props']).to include('enabled' => false, 'pending' => false, 'required' => false)

      post '/support/admin/settings/two_factor/setup'
      enrolment = Escalated::TwoFactor.find_by(user_id: agent.id)
      secret = enrolment.secret
      expect(secret.length).to be >= 32
      expect(enrolment.read_attribute_before_type_cast(:secret)).not_to include(secret)

      post '/support/admin/settings/two_factor/confirm', params: { code: code(secret) }
      expect(enrolment.reload).to be_confirmed
      # Confirming proves the second factor for this session.
      get '/support/agent'
      expect(response).to have_http_status(:ok)
    end

    it 'sends staff without an enrolment to enrol when required, and nowhere else' do
      Escalated.configuration.two_factor = { cache_store: cache, required: true }
      agent = create(:user, :agent)
      sign_in_as(agent)

      get '/support/agent'
      expect(response).to redirect_to('/support/admin/settings/two_factor')
      get '/support/admin/settings/two_factor'
      expect(response).to have_http_status(:ok)
      expect(page.dig('props', 'required')).to be(true)
      expect(page.dig('props', 'escalated', 'two_factor_required')).to be(true)
      post '/support/admin/settings/two_factor/setup'
      expect(Escalated::TwoFactor.where(user_id: agent.id)).to exist
    end

    it 'lets an admin require two-factor at runtime with a partial settings post' do
      Escalated::EscalatedSetting.set('guest_tickets_enabled', '1')
      admin = create(:user, :admin)
      sign_in_as(admin)
      get '/support/agent'
      expect(response).to have_http_status(:ok)

      post '/support/admin/settings', params: { two_factor_required: true }
      expect(Escalated::EscalatedSetting.get('two_factor_required')).to eq('1')
      # Keys the post left out keep their stored value.
      expect(Escalated::EscalatedSetting.get('guest_tickets_enabled')).to eq('1')

      get '/support/agent'
      expect(response).to redirect_to('/support/admin/settings/two_factor')
    end

    it 'does not challenge the token API' do
      user = create(:user, :agent)
      enrol(user)
      token = Escalated::ApiToken.create_token(user, 'two-factor spec')
      get '/support/api/v1/tickets', headers: { 'Authorization' => "Bearer #{token[:plain_text_token]}" }
      expect(response).to have_http_status(:ok)
    end

    it 'reads an enrolment stored before secrets were sealed' do
      user = create(:user, :agent)
      secret = ROTP::Base32.random(20)
      enrolment = Escalated::TwoFactor.create!(user_id: user.id, confirmed_at: Time.current)
      enrolment.update_columns(secret: secret, recovery_codes: ['OLD1-OLD2'])
      sign_in_as(user)

      post challenge, params: { code: code(secret) }
      expect(response).to have_http_status(:see_other)
      get '/support/agent'
      expect(response).to have_http_status(:ok)
    end
  end
end
