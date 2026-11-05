# frozen_string_literal: true

require 'rails_helper'
require 'escalated/seeds/permissions'

# The admin embedded in a host admin panel (ADR 2026-11-05-embeddable-admin),
# layout mode: routes under the host's prefix and guards with the same names,
# Escalated's admin gate kept, the embed flag and the admin menu shared.
RSpec.describe 'Embedded admin: layout mode', type: :request do
  embed_admin_with

  let(:admin) { create(:user, :admin, email: 'embed-admin@example.test') }
  let(:agent) { create(:user, :agent, email: 'embed-agent@example.test') }

  before { allow(Escalated.configuration).to receive(:notification_channels).and_return([]) }

  describe 'routes' do
    it 'mounts the admin under the host prefix with the host guards running' do
      sign_in_as(admin)
      get '/backoffice/helpdesk/tags'

      expect(response).to have_http_status(:ok)
      expect(response.headers['X-Host-Admin']).to eq('1')
      expect(inertia_page['component']).to eq('Escalated/Admin/Tags/Index')
    end

    it 'keeps the route helper names, which now point at the host prefix' do
      helpers = Escalated::Engine.routes.url_helpers
      expect(helpers.admin_tags_path).to eq('/backoffice/helpdesk/tags')
      expect(helpers.admin_plugins_path).to eq('/backoffice/helpdesk/plugins')
      expect(helpers.admin_api_tokens_path).to eq('/backoffice/helpdesk/api_tokens')
      expect(helpers.admin_import_index_path).to eq('/backoffice/helpdesk/import')
      expect(helpers.sdk_plugin_page_path(slug: 'crm', page_route: 'board'))
        .to eq('/backoffice/helpdesk/plugins/crm/board')
    end

    it 'points the frontend route list at the host prefix' do
      routes = Escalated::RouteList.routes

      expect(routes['escalated.admin.tags.index'][:uri]).to eq('backoffice/helpdesk/tags')
      expect(routes['escalated.admin.tickets.show'][:uri]).to eq('backoffice/helpdesk/tickets/{id}')
      expect(routes['escalated.admin.settings.email'][:uri]).to eq('backoffice/helpdesk/settings/email')
      expect(routes['escalated.agent.dashboard'][:uri]).to eq('support/agent')
      expect(routes['escalated.admin.two-factor.index'][:uri]).to eq('support/admin/settings/two-factor')
    end

    it 'no longer serves the standalone admin URLs' do
      sign_in_as(admin)
      %w[/support/admin/tags /support/admin/reports /support/admin/plugins/crm/board].each do |path|
        expect { Rails.application.routes.recognize_path(path) }.to raise_error(ActionController::RoutingError)
      end
    end

    it 'moves every admin screen that lived under /support/admin' do
      admin_routes = Escalated::Engine.routes.routes.select do |route|
        route.defaults[:controller].to_s.start_with?('escalated/admin/') || route.name == 'sdk_plugin_page'
      end
      standalone = %w[escalated/admin/two_factor escalated/admin/newsletters escalated/admin/newsletter_lists
                      escalated/admin/newsletter_templates escalated/admin/newsletter_settings]

      moved, kept = admin_routes.partition { |route| standalone.exclude?(route.defaults[:controller]) }
      expect(moved.map { |route| route.path.spec.to_s }).to all(start_with('/backoffice/helpdesk/'))
      expect(kept.map { |route| route.path.spec.to_s }).to all(start_with('/support/admin/'))
      expect(moved.size).to be > 150
    end

    it 'moves exactly the standalone admin routes, keeping their names and endpoints' do
      before = JSON.parse(File.read(File.expand_path('../../fixtures/embed/default-routes.json', __dir__)))
      key = ->(route) { [route['name'], route['verb'], route['endpoint']] }
      expected = before.dig('ui', 'engine').map do |route|
        path = route['path']
        moved = path.start_with?('/admin/') && !path.start_with?('/admin/settings/two') &&
                !path.start_with?('/admin/newsletters')
        # The engine's root, drawn under the prefix, is /support(.:format).
        path = '(.:format)' if path == '/'
        [key.call(route), moved ? path.sub(%r{\A/admin}, '/backoffice/helpdesk') : "/support#{path}"]
      end
      live = EscalatedRouteTable.engine_routes.map { |route| [key.call(route), route['path']] }

      expect(live.sort_by(&:inspect)).to eq(expected.sort_by(&:inspect))
    end

    it 'leaves the agent panel, customer, guest, widget, two-factor and newsletter routes where they were' do
      helpers = Escalated::Engine.routes.url_helpers
      expect(helpers.agent_dashboard_path).to eq('/support/agent')
      expect(helpers.customer_kb_path).to eq('/support/customer/kb')
      expect(helpers.guest_verification_path).to eq('/support/guest/verification')
      expect(helpers.widget_config_path).to eq('/support/widget/config')
      expect(helpers.admin_settings_two_factor_path).to eq('/support/admin/settings/two_factor')
      expect(helpers.two_factor_challenge_path).to eq('/support/two-factor/challenge')
      expect(helpers.admin_newsletters_path).to eq('/support/admin/newsletters')
      expect(helpers.sdk_plugin_endpoint_path(slug: 'crm')).to eq('/support/api/plugins/crm')
      expect(Rails.application.routes.url_helpers.escalated_api_v1_dashboard_path).to eq('/support/api/v1/dashboard')
    end

    it 'builds page links on the embedded URLs' do
      sign_in_as(admin)
      create_list(:escalated_ticket, 3)
      get '/backoffice/helpdesk/tickets', params: { per_page: 2 }

      links = inertia_page.dig('props', 'tickets', 'links').filter_map { |link| link['url'] }
      expect(links).to include('/backoffice/helpdesk/tickets?page=2&per_page=2')
    end

    it 'keeps the signed attachment links at their URL' do
      attachment = Escalated::Attachment.new(id: 42)
      allow(Escalated::AttachmentAccess).to receive(:ticket_for).and_return(nil)

      expect(Escalated::AttachmentAccess.url(attachment)).to start_with('/support/attachments/42?token=')
    end

    it 'redirects a settings save back to the embedded settings screen' do
      sign_in_as(admin)
      post '/backoffice/helpdesk/settings', params: { settings: { guest_tickets_enabled: '1' } }

      expect(response).to redirect_to('/backoffice/helpdesk/settings')
    end

    it 'still answers the agent panel and the host app' do
      sign_in_as(admin)
      get '/support/agent'
      expect(response).to have_http_status(:ok)
      expect(response.headers).not_to have_key('X-Host-Admin')

      get '/'
      expect(response.body).to eq('dummy host root')
    end
  end

  describe 'gates' do
    it "keeps Escalated's admin gate unless the host opts out of it" do
      sign_in_as(agent)
      get '/backoffice/helpdesk/tags'

      expect(response).to redirect_to('/')
    end

    it "requires the host guard's authentication" do
      get '/backoffice/helpdesk/tags'

      expect(response).to have_http_status(:unauthorized)
    end

    it 'keeps route permissions on the embedded routes' do
      allow(Escalated.configuration).to receive(:access).and_return(roles_permissions: true)
      sign_in_as(admin)
      get '/backoffice/helpdesk/tags'

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'shared props' do
    it 'shares the embed flag on embedded pages' do
      sign_in_as(admin)
      get '/backoffice/helpdesk/tags'

      expect(inertia_page.dig('props', 'escalated', 'embed')).to eq(
        'enabled' => true,
        'mode' => 'layout',
        'layout' => 'Layouts/AdminLayout',
        'route' => 'escalated.admin.tags.index',
        'base_url' => '/backoffice/helpdesk',
        'allowed_origins' => []
      )
    end

    it 'names the current route on a page with parameters' do
      sign_in_as(admin)
      department = create(:escalated_department)
      get "/backoffice/helpdesk/departments/#{department.id}/edit"

      expect(inertia_page.dig('props', 'escalated', 'embed', 'route')).to eq('escalated.admin.departments.edit')
    end

    it 'marks other pages as not embedded but still shares the menu' do
      sign_in_as(admin)
      get '/support/agent'

      escalated = inertia_page.dig('props', 'escalated')
      expect(escalated['embed']).to include('enabled' => false, 'route' => nil)
      expect(escalated['navigation']).not_to be_empty
    end

    it 'adds no framing headers in layout mode' do
      sign_in_as(admin)
      get '/backoffice/helpdesk/tags'

      expect(response.headers).not_to have_key('Content-Security-Policy')
      expect(response.headers['X-Frame-Options']).to eq('SAMEORIGIN')
    end
  end

  describe 'navigation' do
    it 'shares the admin menu with the documented item shape, in order, with the active item' do
      sign_in_as(admin)
      get '/backoffice/helpdesk/tags'

      items = inertia_page.dig('props', 'escalated', 'navigation')
      expect(items.first).to eq(
        'key' => 'reports', 'label' => 'Reports', 'route' => 'escalated.admin.reports',
        'url' => '/backoffice/helpdesk/reports', 'icon' => 'reports', 'position' => 10,
        'active' => false, 'badge' => nil, 'plugin' => nil, 'children' => []
      )
      expect(items.second['key']).to eq('tickets')
      expect(items.find { |item| item['active'] }['key']).to eq('tags')
      expect(items.pluck('position')).to eq(items.pluck('position').sort)
      expect(items.last['key']).to eq('settings')
    end

    it 'marks the item active on a page below it' do
      department = create(:escalated_department)
      items = Escalated.admin_navigation(admin, path: "/backoffice/helpdesk/departments/#{department.id}/edit")

      expect(items.select { |item| item[:active] }.pluck(:key)).to eq(['departments'])
    end

    it 'leaves out screens whose feature is off' do
      keys = Escalated.admin_navigation(admin).pluck(:key)

      # Roles & permissions, newsletters and plugins are off by default here;
      # the API is on in the dummy app.
      expect(keys).not_to include('roles', 'newsletters', 'plugins')
      expect(keys).to include('tags', 'settings', 'api-tokens', 'import')
    end

    it 'lists the features that are on' do
      allow(Escalated.configuration).to receive_messages(enable_newsletters?: true, plugins_enabled: true,
                                                         access: { roles_permissions: false })
      items = Escalated.admin_navigation(admin)

      expect(items.pluck(:key)).to include('newsletters', 'plugins')
      expect(items.find { |item| item[:key] == 'newsletters' })
        .to include(route: nil, url: '/support/admin/newsletters', position: 81)
    end

    it 'filters the menu by route permission while roles & permissions is on' do
      allow(Escalated.configuration).to receive(:access).and_return(roles_permissions: true)
      Escalated::Seeds::Permissions.seed!
      role = Escalated::Role.create!(name: 'Tag keeper')
      role.permissions = Escalated::Permission.where(slug: %w[tag.view ticket.view])
      role.users << admin

      keys = Escalated.admin_navigation(admin).pluck(:key)

      expect(keys).to include('tags', 'tickets')
      expect(keys).not_to include('settings', 'users', 'roles')
    end

    it 'gives no menu to a user who may not use the admin' do
      expect(Escalated.admin_navigation(agent)).to eq([])
      expect(Escalated.admin_navigation(nil)).to eq([])

      sign_in_as(agent)
      get '/support/agent'
      expect(inertia_page.dig('props', 'escalated', 'navigation')).to eq([])
    end

    it 'includes plugin admin menu items, sorted in by position' do
      Escalated.plugin_ui.add_menu_item(label: 'CRM', url: '/backoffice/helpdesk/crm', icon: 'crm', position: 61,
                                        section: 'admin', plugin: 'crm', badge: 3,
                                        submenu: [{ label: 'Boards', url: '/backoffice/helpdesk/crm/boards' }])
      items = Escalated.admin_navigation(admin)
      crm = items.find { |item| item[:label] == 'CRM' }

      expect(crm).to include(key: 'plugin:crm:0', route: nil, url: '/backoffice/helpdesk/crm', icon: 'crm',
                             badge: 3, plugin: 'crm', position: 61)
      expect(crm[:children]).to eq([{ label: 'Boards', url: '/backoffice/helpdesk/crm/boards', icon: nil }])
      expect(items.index(crm)).to eq(items.index { |item| item[:key] == 'tags' } + 1)
    ensure
      Escalated.plugin_ui.clear!
    end

    it 'leaves agent-section plugin items out' do
      Escalated.plugin_ui.add_menu_item(label: 'Queue tools', url: '/x', section: 'agent', plugin: 'q')

      expect(Escalated.admin_navigation(admin).pluck(:label)).not_to include('Queue tools')
    ensure
      Escalated.plugin_ui.clear!
    end
  end
end
