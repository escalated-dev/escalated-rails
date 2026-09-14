# frozen_string_literal: true

require 'cgi'
require 'json'
require 'rails_helper'

# The SSO settings screen shows the settings SsoService actually reads.
#
# It used to render a page name the frontend does not ship -- so the screen came
# up blank -- and behind that it showed a different, OIDC-shaped set of keys
# (sso_client_id, sso_issuer) which SsoService has never consulted, while hiding
# every key it does. The form saved values nothing used.
RSpec.describe 'Admin SSO settings', type: :request do
  let(:admin) { create(:user, :admin, email: 'admin-sso-settings@example.test') }

  before { allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(admin) } # rubocop:disable RSpec/AnyInstance

  def page_payload
    encoded = response.body[%r{data-page="(.+?)"></div>}m, 1]
    raise 'missing Inertia page payload' unless encoded

    JSON.parse(CGI.unescapeHTML(encoded))
  end

  it 'renders the component the frontend ships' do
    get '/support/admin/settings/sso'

    expect(response).to have_http_status(:ok)
    expect(page_payload['component']).to eq('Escalated/Admin/Settings/SsoSettings')
  end

  it 'shows every key SsoService reads' do
    get '/support/admin/settings/sso'

    settings = page_payload['props']['settings']

    expect(settings.keys).to match_array(Escalated::Services::SsoService::CONFIG_KEYS)
  end

  it 'saves through the service, so what is entered is what SSO reads' do
    post '/support/admin/settings/sso', params: {
      sso_provider: 'saml',
      sso_entity_id: 'https://example.test/sso',
      sso_attr_email: 'mail'
    }

    expect(response).to be_redirect
    expect(Escalated::Services::SsoService.new.get_config).to include(
      'sso_provider' => 'saml',
      'sso_entity_id' => 'https://example.test/sso',
      'sso_attr_email' => 'mail'
    )
  end

  it 'leaves keys it was not given alone' do
    Escalated::EscalatedSetting.find_or_initialize_by(key: 'sso_certificate').update!(value: 'kept')

    post '/support/admin/settings/sso', params: { sso_provider: 'jwt' }

    expect(Escalated::Services::SsoService.new.get_config['sso_certificate']).to eq('kept')
  end
end
