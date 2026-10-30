# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

# domain-model/plugin-contract.md: SDK plugins are listed on Admin > Plugins,
# activated and deactivated there like Ruby ones, and only active SDK plugins
# get hooks, endpoints, webhooks, cron, badges and UI extensions. The runtime
# loads every installed plugin, so these run the real stdio bridge against a
# stand-in runtime that logs what the host sends it.
RSpec.describe 'SDK plugin activation', type: :request do
  let(:admin) { create(:user, :admin, email: 'sdk-admin@example.test') }
  let(:agent) { create(:user, :agent, email: 'sdk-agent@example.test') }
  let(:viewer) { admin }
  let(:runtime_log) { File.join(Dir.tmpdir, "esc-plugin-runtime-#{SecureRandom.hex(6)}.log") }
  let(:fixture) { File.expand_path('../../fixtures/plugin_activation_runtime.rb', __dir__) }

  before do
    Escalated.reset_plugins!
    File.write(runtime_log, '')
    allow(Escalated.configuration).to receive_messages(
      sdk_plugins_enabled: true, notification_channels: [], webhook_url: nil,
      plugin_runtime_command: "#{RbConfig.ruby} #{fixture} #{runtime_log}", plugin_runtime_cwd: Dir.tmpdir
    )
    allow(Escalated::Broadcasting).to receive(:broadcast)
    # Node is not needed: the stand-in runtime is a Ruby script.
    allow_any_instance_of(Escalated::Bridge::PluginBridge) # rubocop:disable RSpec/AnyInstance
      .to receive(:runtime_available?).and_return(true)
    allow_any_instance_of(Escalated::ApplicationController) # rubocop:disable RSpec/AnyInstance
      .to receive(:current_user) { viewer }
  end

  after do
    Escalated.plugin_bridge.shutdown
    Escalated.reset_plugins!
    FileUtils.rm_f(runtime_log)
  end

  # Boot the real bridge. With recorded, SDK plugins were already recorded
  # (an install that has used this version).
  def boot_runtime(recorded: true)
    Escalated::EscalatedSetting.set(Escalated::Bridge::SdkPluginActivation::RECORDED_SETTING, 'yes') if recorded
    bridge = Escalated.plugin_bridge
    bridge.boot
    expect(bridge).to be_booted
    bridge
  end

  # What the host sent the runtime since the last call. Badges are left
  # out unless asked for: every rendered page asks them.
  def runtime_saw(except: %w[ping badge])
    lines = File.readlines(runtime_log, chomp: true).reject(&:empty?)
    File.write(runtime_log, '')
    lines.map { |line| JSON.parse(line) }.reject { |entry| except.include?(entry['method']) }
  end

  def index_plugins
    get '/support/admin/plugins'
    expect(response).to have_http_status(:ok)
    inertia_page['props']['plugins'].index_by { |p| p['slug'] }
  end

  def lifecycle(hook)
    { 'method' => 'action', 'params' => {
      'hook' => hook, 'event' => { 'plugin' => '@acme/plugin-crm', 'slug' => 'acme--plugin-crm' },
      'plugins' => ['@acme/plugin-crm']
    } }
  end

  describe 'Admin > Plugins' do
    it 'lists SDK plugins by slug, inactive until activated' do
      boot_runtime

      plugins = index_plugins

      expect(plugins.keys).to include('acme--plugin-crm', 'acme--plugin-quiet')
      expect(plugins['acme--plugin-crm']).to include(
        'name' => '@acme/plugin-crm', 'version' => '1.2.3', 'description' => 'CRM plugin',
        'is_active' => false, 'activated_at' => nil, 'source' => 'composer',
        'provides' => { 'menu_items' => 1, 'widgets' => 1, 'page_components' => 1 }
      )
      expect(inertia_page['props']['can_upload']).to be(true)
    end

    it 'records the SDK plugins already installed as active the first time it sees them' do
      boot_runtime(recorded: false)

      expect(Escalated::Plugin.where(is_active: true).pluck(:slug))
        .to contain_exactly('acme--plugin-crm', 'acme--plugin-quiet')

      Escalated::Plugin.find_by(slug: 'acme--plugin-quiet').update!(is_active: false)
      Escalated.plugin_bridge.shutdown
      Escalated.reset_plugins!
      boot_runtime(recorded: false)

      expect(Escalated::Plugin.find_by(slug: 'acme--plugin-quiet').is_active).to be(false)
    end

    it "activates: the row, the runtime's activate, then plugin.activated; again does nothing" do
      boot_runtime
      runtime_saw

      post '/support/admin/plugins/acme--plugin-crm/activate'

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to('/support/admin/plugins')
      expect(flash[:success]).to be_present
      row = Escalated::Plugin.find_by(slug: 'acme--plugin-crm')
      expect([row.is_active, row.activated_at.present?, row.deactivated_at]).to eq([true, true, nil])
      expect(runtime_saw).to eq([
                                  { 'method' => 'activate', 'params' => { 'plugin' => '@acme/plugin-crm' } },
                                  lifecycle('plugin.activated')
                                ])

      post '/support/admin/plugins/acme--plugin-crm/activate'
      expect(response).to have_http_status(:see_other)
      expect(runtime_saw).to eq([])
    end

    it "deactivates: plugin.deactivated and the runtime's deactivate while active, then the row" do
      boot_runtime
      activate_sdk_plugins('@acme/plugin-crm')
      runtime_saw

      post '/support/admin/plugins/acme--plugin-crm/deactivate'

      expect(response).to have_http_status(:see_other)
      expect(flash[:success]).to be_present
      row = Escalated::Plugin.find_by(slug: 'acme--plugin-crm')
      expect([row.is_active, row.deactivated_at.present?]).to eq([false, true])
      expect(runtime_saw).to eq([
                                  lifecycle('plugin.deactivated'),
                                  { 'method' => 'deactivate', 'params' => { 'plugin' => '@acme/plugin-crm' } }
                                ])

      post '/support/admin/plugins/acme--plugin-crm/deactivate'
      expect(runtime_saw).to eq([])
    end

    it 'refuses an unknown slug without a row: an error flash, or 404 for JSON' do
      boot_runtime

      post '/support/admin/plugins/acme--plugin-nope/activate'
      expect(response).to have_http_status(:see_other)
      expect(flash[:error]).to be_present

      post '/support/admin/plugins/acme--plugin-nope/activate', headers: { 'Accept' => 'application/json' }
      expect(response).to have_http_status(:not_found)
      expect(Escalated::Plugin.exists?(slug: 'acme--plugin-nope')).to be(false)
    end

    it 'refuses to uninstall an SDK plugin, which npm manages' do
      boot_runtime
      activate_sdk_plugins('@acme/plugin-crm')

      delete '/support/admin/plugins/acme--plugin-crm'

      expect(response).to have_http_status(:redirect)
      expect(Escalated::Plugin.find_by(slug: 'acme--plugin-crm').is_active).to be(true)
    end

    context 'as an agent' do
      let(:viewer) { agent }

      it 'is refused' do
        boot_runtime
        post '/support/admin/plugins/acme--plugin-crm/activate'

        expect(response).to have_http_status(:redirect)
        expect(Escalated::Plugin.exists?(slug: 'acme--plugin-crm')).to be(false)
      end
    end
  end

  describe 'only active SDK plugins are reached' do
    it 'sends actions and filters naming the active plugins, and nothing when none is active' do
      bridge = boot_runtime
      runtime_saw

      bridge.dispatch_action('ticket.created', { 'id' => 1 })
      expect(bridge.apply_filter('import.adapters', ['x'])).to eq(['x'])
      expect(runtime_saw).to eq([])

      activate_sdk_plugins('@acme/plugin-crm')
      bridge.dispatch_action('ticket.created', { 'id' => 1 })
      bridge.apply_filter('import.adapters', ['x'])

      expect(runtime_saw.map { |m| [m['method'], m['params']['plugins']] })
        .to eq([['action', ['@acme/plugin-crm']], ['filter', ['@acme/plugin-crm']]])
    end

    it 'refuses ctx calls from an inactive plugin the runtime still dispatched to' do
      bridge = boot_runtime
      activate_sdk_plugins('@acme/plugin-crm')
      runtime_saw

      bridge.dispatch_action('test.ctx', {})

      answers = runtime_saw.select { |m| m['method'] == 'ctx-answer' }.index_by { |m| m['plugin'] }
      expect(answers['@acme/plugin-crm']['answer']).to eq('result' => nil)
      expect(answers['@acme/plugin-quiet']['answer']).to have_key('error')
      expect(Escalated::PluginStoreRecord.where(plugin: '@acme/plugin-quiet')).not_to exist
      expect(Escalated::PluginStoreRecord.where(plugin: '@acme/plugin-crm')).to exist
    end

    it "answers an inactive plugin's endpoints and webhooks 404 without asking the runtime" do
      boot_runtime
      activate_sdk_plugins('@acme/plugin-crm')
      runtime_saw

      expect(plugin_route(Escalated::Plugins::EndpointsController, '@acme/plugin-quiet', :endpoint_path).first)
        .to eq(404)
      expect(plugin_route(Escalated::Plugins::WebhooksController, '@acme/plugin-quiet', :webhook_path).first)
        .to eq(404)
      expect(runtime_saw).to eq([])

      expect(plugin_route(Escalated::Plugins::EndpointsController, '@acme/plugin-crm', :endpoint_path).first)
        .to eq(200)
      expect(plugin_route(Escalated::Plugins::WebhooksController, '@acme/plugin-crm', :webhook_path).first)
        .to eq(200)
      expect(runtime_saw.map { |m| [m['method'], m['params']['plugin']] })
        .to eq([['endpoint', '@acme/plugin-crm'], ['webhook', '@acme/plugin-crm']])
    end

    it 'runs cron only for active plugins' do
      bridge = boot_runtime
      activate_sdk_plugins('@acme/plugin-crm')
      runtime_saw

      Escalated::Services::PluginCron.run_due(Time.utc(2026, 10, 29, 9, 0), bridge: bridge)

      expect(runtime_saw).to eq([{ 'method' => 'cron',
                                   'params' => { 'plugin' => '@acme/plugin-crm', 'schedule' => '* * * * *' } }])
    end

    it 'shares widgets with badges and slots of active plugins only' do
      boot_runtime
      activate_sdk_plugins('@acme/plugin-crm')
      runtime_saw

      get '/support/agent'
      plugins = inertia_page['props']['escalated']['plugins']

      expect(plugins['dashboardWidgets'].map { |w| [w['plugin'], w['badge']] }).to eq([['acme--plugin-crm', 5]])
      expect(plugins['pageComponents']['ticket.show.sidebar'].pluck('plugin')).to eq(['acme--plugin-crm'])
      expect(runtime_saw(except: []).select { |m| m['method'] == 'badge' }.map { |m| m['params']['plugin'] })
        .to eq(['@acme/plugin-crm'])
    end
  end

  describe 'Ruby plugins' do
    it 'fire plugin.activated, plugin.uninstalling and plugin.deactivated, and a raising one undoes nothing' do
      dir = File.join(Escalated::Services::PluginService.plugins_path, 'native-life')
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, 'plugin.json'), JSON.generate('name' => 'Native Life'))
      File.write(File.join(dir, 'plugin.rb'), '# noop')
      seen = []
      %w[plugin.activated plugin.deactivated plugin.uninstalling].each do |hook|
        Escalated.hooks.add_action(hook) do |payload|
          seen << [hook, payload]
          raise 'plugin broke'
        end
      end

      post '/support/admin/plugins/native-life/activate'
      expect(Escalated::Plugin.find_by(slug: 'native-life').is_active).to be(true)
      delete '/support/admin/plugins/native-life'

      payload = { 'plugin' => 'Native Life', 'slug' => 'native-life' }
      expect(seen).to eq([['plugin.activated', payload], ['plugin.uninstalling', payload],
                          ['plugin.deactivated', payload]])
      expect(Escalated::Plugin.exists?(slug: 'native-life')).to be(false)
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  # Runs an SDK plugin route's controller through Rack, as the routes the
  # bridge draws do.
  def plugin_route(controller, plugin, path_key)
    env = Rack::MockRequest.env_for('/support/plugins/x', method: 'POST', input: '{}',
                                                          'CONTENT_TYPE' => 'application/json')
    env['action_dispatch.request.path_parameters'] = {
      controller: controller.controller_path, action: 'handle', plugin: plugin, path_key => 'ping'
    }
    controller.action(:handle).call(env)
  end
end
