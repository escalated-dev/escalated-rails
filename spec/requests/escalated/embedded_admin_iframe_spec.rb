# frozen_string_literal: true

require 'rails_helper'

# iframe mode (ADR 2026-11-05-embeddable-admin): only the configured origins
# may frame the embedded admin, and only embedded responses change.
#
# The engine inserts Escalated::EmbedFrameHeaders at the top of the host's Rack
# stack when embedding is on at boot (spec/lib/escalated/embed_config_spec.rb
# checks that); the dummy app boots with it off, so these examples put it in
# the same place, around a host middleware that sends its own framing headers.
RSpec.describe 'Embedded admin: iframe mode', type: :request do
  embed_admin_with(mode: 'iframe',
                   frame_ancestors: ['https://admin.example.com', 'https://*.evil.example', '*',
                                     'https://admin.example.com/', 'javascript:alert(1)', 'https://x.test/path'])

  let(:admin) { create(:user, :admin, email: 'embed-iframe-admin@example.test') }
  let(:host_csp) { nil }

  def app
    Escalated::EmbedFrameHeaders.new(EmbedHelpers::HostFrameHeaders.new(Rails.application, csp: host_csp))
  end

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    sign_in_as(admin)
  end

  it 'lets only the allow-listed origins frame an embedded page' do
    get '/backoffice/helpdesk/tags'

    expect(response).to have_http_status(:ok)
    expect(response.headers['Content-Security-Policy']).to eq("frame-ancestors 'self' https://admin.example.com")
    expect(response.headers).not_to have_key('X-Frame-Options')
  end

  it "leaves every other response's framing headers alone" do
    get '/support/agent'

    expect(response).to have_http_status(:ok)
    expect(response.headers).not_to have_key('Content-Security-Policy')
    expect(response.headers['X-Frame-Options']).to eq('DENY')
  end

  it 'shares the allow-list, without wildcards, for the postMessage bridge' do
    get '/backoffice/helpdesk/tags'

    expect(inertia_page.dig('props', 'escalated', 'embed')).to include(
      'enabled' => true, 'mode' => 'iframe', 'allowed_origins' => ['https://admin.example.com']
    )
  end

  context 'when the host sends a policy of its own' do
    let(:host_csp) { "script-src 'self'" }

    it 'keeps it and adds frame-ancestors as a second policy' do
      get '/backoffice/helpdesk/tags'

      expect(response.headers['Content-Security-Policy'])
        .to eq("script-src 'self', frame-ancestors 'self' https://admin.example.com")
    end
  end

  it 'allows only same-origin framing when no origins are configured' do
    Escalated.configuration.embed = Escalated.configuration.embed.merge(frame_ancestors: [])
    get '/backoffice/helpdesk/tags'

    expect(response.headers['Content-Security-Policy']).to eq("frame-ancestors 'self'")
  end
end
