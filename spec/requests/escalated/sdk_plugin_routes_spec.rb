# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require 'escalated/seeds/permissions'

# domain-model/plugin-contract.md, Pages and Endpoints and webhooks: an SDK
# plugin's pages are {prefix}/admin/plugins/{slug}/{route} rendering
# Escalated/Plugin/Page, its endpoints {prefix}/api/plugins/{slug}{path}
# behind the admin guard, its webhooks {prefix}/webhooks/plugins/{slug}{path}
# with no guard, and only active plugins answer. These run the real stdio
# bridge against the stand-in runtime, through the engine's routes.
RSpec.describe 'SDK plugin pages, endpoints and webhooks', type: :request do
  let(:admin) { create(:user, :admin, email: 'sdk-routes-admin@example.test') }
  let(:agent) { create(:user, :agent, email: 'sdk-routes-agent@example.test') }
  let(:viewer) { admin }
  let(:runtime_log) { File.join(Dir.tmpdir, "esc-plugin-routes-#{SecureRandom.hex(6)}.log") }
  let(:fixture) { File.expand_path('../../fixtures/plugin_activation_runtime.rb', __dir__) }

  before do
    Escalated.reset_plugins!
    File.write(runtime_log, '')
    allow(Escalated.configuration).to receive_messages(
      sdk_plugins_enabled: true, notification_channels: [], webhook_url: nil,
      plugin_runtime_command: "#{RbConfig.ruby} #{fixture} #{runtime_log}", plugin_runtime_cwd: Dir.tmpdir
    )
    allow(Escalated::Broadcasting).to receive(:broadcast)
    allow_any_instance_of(Escalated::Bridge::PluginBridge) # rubocop:disable RSpec/AnyInstance
      .to receive(:runtime_available?).and_return(true)
    allow_any_instance_of(Escalated::ApplicationController) # rubocop:disable RSpec/AnyInstance
      .to receive(:current_user) { viewer }
    Escalated::EscalatedSetting.set(Escalated::Bridge::SdkPluginActivation::RECORDED_SETTING, 'yes')
    Escalated.plugin_bridge.boot
    activate_sdk_plugins('@acme/plugin-crm')
    runtime_saw
  end

  after do
    Escalated.plugin_bridge.shutdown
    Escalated.reset_plugins!
    Escalated.configuration.access = {}
    FileUtils.rm_f(runtime_log)
  end

  def runtime_saw
    lines = File.readlines(runtime_log, chomp: true).reject(&:empty?)
    File.write(runtime_log, '')
    lines.map { |line| JSON.parse(line) }.reject { |entry| %w[ping badge].include?(entry['method']) }
  end

  describe 'pages' do
    it 'renders Escalated/Plugin/Page with the plugin name, component, layout and its GET /{component} props' do
      get '/support/admin/plugins/acme--plugin-crm/settings'

      expect(response).to have_http_status(:ok)
      expect(inertia_page['component']).to eq('Escalated/Plugin/Page')
      props = inertia_page['props']
      expect(props.slice('plugin', 'component', 'layout'))
        .to eq('plugin' => '@acme/plugin-crm', 'component' => 'Settings', 'layout' => 'admin')
      expect(props['props']).to include('plugin' => '@acme/plugin-crm', 'path' => '/Settings')
    end

    it "answers an inactive or unknown plugin's page, an unknown page and the raw name 404" do
      get '/support/admin/plugins/acme--plugin-quiet/settings'
      expect(response).to have_http_status(:not_found)
      get '/support/admin/plugins/acme--plugin-nope/settings'
      expect(response).to have_http_status(:not_found)
      get '/support/admin/plugins/acme--plugin-crm/elsewhere'
      expect(response).to have_http_status(:not_found)
      expect(runtime_saw).to eq([])
    end

    it 'shares the menu entry of an active plugin page, pointing at the page' do
      get '/support/agent'

      menu = inertia_page['props']['escalated']['plugins']['menuItems']
      expected = { 'label' => 'CRM', 'route' => '/support/admin/plugins/acme--plugin-crm/settings',
                   'section' => 'admin', 'plugin' => 'acme--plugin-crm' }
      expect(menu.map { |m| m.slice('label', 'route', 'section', 'plugin') }).to eq([expected])
    end

    context 'as an agent' do
      let(:viewer) { agent }

      it 'is refused' do
        get '/support/admin/plugins/acme--plugin-crm/settings'
        expect(response).not_to have_http_status(:ok)
        expect(runtime_saw.pluck('method')).not_to include('endpoint')
      end
    end
  end

  describe 'endpoints' do
    it 'are mounted on the slug and receive route params, query, body and no credentials' do
      post '/support/api/plugins/acme--plugin-crm/items/42?sort=asc', params: { name: 'x' }.to_json,
                                                                      headers: {
                                                                        'CONTENT_TYPE' => 'application/json',
                                                                        'Authorization' => 'Bearer t',
                                                                        'Cookie' => 'a=b', 'X-Custom' => 'kept'
                                                                      }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.slice('plugin', 'path', 'params', 'query', 'body')).to eq(
        'plugin' => '@acme/plugin-crm', 'path' => '/items/:id', 'params' => { 'id' => '42' },
        'query' => { 'sort' => 'asc' }, 'body' => { 'name' => 'x' }
      )
      expect(body['headers'].keys.map(&:downcase)).to include('x-custom')
      expect(body['headers'].keys.map(&:downcase)).not_to include('authorization', 'cookie')
    end

    it 'answers the raw name, an inactive plugin and an undeclared path 404 without asking the runtime' do
      get '/support/api/plugins/@acme/plugin-crm/ping'
      expect(response).to have_http_status(:not_found)
      get '/support/api/plugins/acme--plugin-quiet/ping'
      expect(response).to have_http_status(:not_found)
      get '/support/api/plugins/acme--plugin-crm/nothing-here'
      expect(response).to have_http_status(:not_found)
      expect(runtime_saw).to eq([])
    end

    it 'answers a throwing endpoint 500 without its message' do
      get '/support/api/plugins/acme--plugin-crm/boom'

      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).not_to include('secret stack detail')
    end

    it 'enforces a declared capability with 403' do
      Escalated::Seeds::Permissions.seed!
      Escalated::Role.find_by!(slug: 'admin').users << admin
      Escalated.configuration.access = { roles_permissions: true }

      get '/support/api/plugins/acme--plugin-crm/secret'
      expect(response).to have_http_status(:forbidden)
      get '/support/api/plugins/acme--plugin-crm/ping'
      expect(response).to have_http_status(:ok)
    end

    context 'as an agent' do
      let(:viewer) { agent }

      it 'is refused' do
        get '/support/api/plugins/acme--plugin-crm/ping'
        expect(response).not_to have_http_status(:ok)
        expect(runtime_saw).to eq([])
      end
    end
  end

  describe 'webhooks' do
    let(:viewer) { nil }

    it 'answer without auth on the slug, and 404 for an inactive plugin or the raw name' do
      post '/support/webhooks/plugins/acme--plugin-crm/hook', params: '{"a":1}',
                                                              headers: { 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.slice('plugin', 'path', 'body'))
        .to eq('plugin' => '@acme/plugin-crm', 'path' => '/hook', 'body' => { 'a' => 1 })

      post '/support/webhooks/plugins/acme--plugin-quiet/hook'
      expect(response).to have_http_status(:not_found)
      post '/support/webhooks/plugins/@acme/plugin-crm/hook'
      expect(response).to have_http_status(:not_found)
    end
  end
end
