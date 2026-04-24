# frozen_string_literal: true

module Escalated
  class Engine < ::Rails::Engine
    isolate_namespace Escalated

    initializer 'escalated.configuration' do |app|
      # Allow host app to configure Escalated before boot
    end

    initializer 'escalated.i18n' do
      config.i18n.load_path += Dir[root.join('config', 'locales', '*.yml')]
    end

    initializer 'escalated.assets' do |app|
      next unless Escalated.configuration.ui_enabled?

      # Make engine assets available to host app
      app.config.assets.precompile += %w[escalated_manifest.js] if app.config.respond_to?(:assets)
    end

    initializer 'escalated.migrations' do |app|
      unless app.root.to_s.match?(root.to_s)
        config.paths['db/migrate'].expanded.each do |expanded_path|
          app.config.paths['db/migrate'] << expanded_path
        end
      end
    end

    initializer 'escalated.pundit' do
      ActiveSupport.on_load(:action_controller) do
        # Pundit policies are auto-discovered via namespace
      end
    end

    initializer 'escalated.append_routes' do |app|
      app.routes.append do
        mount Escalated::Engine, at: "/#{Escalated.configuration.route_prefix}"
      end
    end

    initializer 'escalated.api_routes' do |app|
      # Conditionally load API routes when api_enabled is true.
      # These are mounted directly on the host app (not inside the engine mount)
      # so they can use ActionController::API without CSRF.
      app.routes.append do
        if Escalated.configuration.api_enabled
          scope Escalated.configuration.api_prefix, module: 'escalated/api/v1', as: 'escalated_api_v1' do
            post 'auth/validate', to: 'auth#validate'
            get 'dashboard', to: 'dashboard#index'

            resources :tickets, param: :reference, only: %i[index show create destroy] do
              member do
                post :reply
                patch :status
                patch :priority
                post :assign
                post :follow
                post :apply_macro
                post :tags
              end
            end

            get 'agents', to: 'resources#agents'
            get 'departments', to: 'resources#departments'
            get 'tags', to: 'resources#tags'
            get 'canned-responses', to: 'resources#canned_responses'
            get 'macros', to: 'resources#macros'
            get 'realtime/config', to: 'resources#realtime_config'
          end
        end
      end
    end

    initializer 'escalated.inertia' do
      next unless Escalated.configuration.ui_enabled?

      ActiveSupport.on_load(:action_controller) do
        # Configure Inertia shared data at engine level
      end
    end

    # Set default plugins_path to Rails.root/lib/escalated/plugins when not
    # explicitly configured. Must run after the host app has booted so
    # Rails.root is available.
    initializer 'escalated.plugins_path', after: :load_config_initializers do |app|
      if Escalated.configuration.plugins_path.nil?
        Escalated.configuration.plugins_path = app.root.join('lib', 'escalated', 'plugins').to_s
      end
    end

    # Wire the WorkflowEngine to the NotificationService's event stream
    # (via ActiveSupport::Notifications). Without this subscription the
    # engine is defined but never invoked — matching the fix pattern
    # applied in escalated-nestjs and the ProcessWorkflows listener in
    # escalated-laravel.
    config.after_initialize do
      Escalated::Services::WorkflowSubscriber.subscribe!
    end

    # Load active plugins after the host app has finished booting so all
    # models, routes, and services are available to plugin code.
    config.after_initialize do
      if Escalated.configuration.plugins_enabled?
        begin
          Escalated::Services::PluginService.load_active_plugins
        rescue StandardError => e
          Rails.logger.error("[Escalated::Engine] Failed to load plugins: #{e.message}")
        end
      end

      # Boot the SDK plugin bridge (Node.js runtime) if configured.
      # This is intentionally after the Ruby plugin system so both can coexist.
      if Escalated.configuration.respond_to?(:sdk_plugins_enabled) &&
         Escalated.configuration.sdk_plugins_enabled
        begin
          Escalated.plugin_bridge.boot
        rescue StandardError => e
          Rails.logger.error("[Escalated::Engine] Failed to boot plugin bridge: #{e.message}")
        end
      end

      # Register bridge hook callbacks so every host-side hook is also
      # forwarded to the Node.js runtime (when the bridge is booted).
      Escalated::Engine.register_bridge_hooks
    end

    # Register bridge forwarding callbacks for every action hook in the
    # HookRegistry.  Each callback forwards the event to the Node.js runtime
    # via PluginBridge#dispatch_action.  This method is idempotent — it only
    # adds callbacks once and is safe to call multiple times.
    def self.register_bridge_hooks
      return if @bridge_hooks_registered

      Escalated::Services::HookRegistry.actions.each_key do |hook|
        Escalated.hooks.add_action(hook, priority: 100) do |*args|
          bridge = Escalated.plugin_bridge
          next unless bridge.booted?

          # Serialize args to a plain hash/array for JSON transport.
          event = { 'args' => args.map { |a| a.respond_to?(:as_json) ? a.as_json : a } }
          bridge.dispatch_action(hook, event)
        end
      end

      @bridge_hooks_registered = true
    end

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot, dir: 'spec/factories'
    end

    # Expose escalated:import:* rake tasks to the host app
    rake_tasks do
      load 'tasks/escalated_import.rake'
      load 'tasks/escalated_chat.rake'
    end
  end
end
