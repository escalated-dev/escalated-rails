# frozen_string_literal: true

require 'rails_helper'

# Embedding the admin in the host's own admin panel (ADR
# 2026-11-05-embeddable-admin) is optional. With no embed configuration every
# Escalated route is exactly what it was before the feature existed (verb,
# path, controller#action, before_action guards, and the Rack middleware
# stack), the standalone admin renders as before, no embed or navigation props
# are shared and no framing headers change.
#
# spec/fixtures/embed/default-routes.json was taken from main before
# embedding was added (see spec/support/escalated_route_table.rb).
RSpec.describe 'Embeddable admin: the default is unchanged', type: :request do
  let(:admin) { create(:user, :admin, email: 'embed-default-admin@example.test') }
  let(:agent) { create(:user, :agent, email: 'embed-default-agent@example.test') }

  def sign_in(user)
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)
  end

  def snapshot_path
    File.expand_path('../../fixtures/embed/default-routes.json', __dir__)
  end

  def live_table
    ui = EscalatedRouteTable.snapshot
    Escalated.configuration.ui_enabled = false
    Rails.application.reload_routes!
    { 'ui' => ui, 'headless' => EscalatedRouteTable.snapshot }
  ensure
    Escalated.configuration.ui_enabled = true
    Rails.application.reload_routes!
  end

  before { allow(Escalated.configuration).to receive(:notification_channels).and_return([]) }

  it 'is off by default' do
    expect(Escalated::Configuration.new.embed).to include(enabled: false, mode: 'layout', prefix: 'admin/support')
    expect(Escalated::Support::EmbedConfig.enabled?).to be(false)
    expect(Rails.application.middleware.map(&:klass)).not_to include(Escalated::EmbedFrameHeaders)
  end

  it 'registers every Escalated route exactly as before' do
    table = live_table
    if ENV['ESCALATED_WRITE_ROUTE_SNAPSHOT'] == '1'
      FileUtils.mkdir_p(File.dirname(snapshot_path))
      File.write(snapshot_path, "#{JSON.pretty_generate(table)}\n")
    end

    expect(table).to eq(JSON.parse(File.read(snapshot_path)))
  end

  it 'serves the standalone admin at the usual URL with no embed or navigation props' do
    sign_in(admin)
    get '/support/admin/tags'

    expect(response).to have_http_status(:ok)
    page = inertia_page
    expect(page['component']).to eq('Escalated/Admin/Tags/Index')
    expect(page.dig('props', 'escalated')).not_to have_key('embed')
    expect(page.dig('props', 'escalated')).not_to have_key('navigation')
    expect(page.dig('props', 'ziggy', 'routes', 'escalated.admin.tags.index', 'uri')).to eq('support/admin/tags')
  end

  it 'leaves the framing headers alone' do
    sign_in(admin)
    get '/support/admin/tags'

    expect(response.headers).not_to have_key('Content-Security-Policy')
    expect(response.headers['X-Frame-Options']).to eq('SAMEORIGIN')
  end

  it 'keeps the admin gate on the standalone admin' do
    sign_in(agent)
    get '/support/admin/tags'

    expect(response).to redirect_to('/')
  end

  it 'lists the standalone admin from the navigation helper while embedding is off' do
    items = Escalated.admin_navigation(admin)

    expect(items.first).to include(key: 'reports', url: '/support/admin/reports')
    expect(items.pluck(:url)).to all(start_with('/support/admin/'))
  end
end
