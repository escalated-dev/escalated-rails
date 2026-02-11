module Escalated
  class Engine < ::Rails::Engine
    isolate_namespace Escalated

    initializer "escalated.configuration" do |app|
      # Allow host app to configure Escalated before boot
    end

    initializer "escalated.assets" do |app|
      # Make engine assets available to host app
      app.config.assets.precompile += %w[escalated_manifest.js] if app.config.respond_to?(:assets)
    end

    initializer "escalated.migrations" do |app|
      unless app.root.to_s.match?(root.to_s)
        config.paths["db/migrate"].expanded.each do |expanded_path|
          app.config.paths["db/migrate"] << expanded_path
        end
      end
    end

    initializer "escalated.pundit" do
      ActiveSupport.on_load(:action_controller) do
        # Pundit policies are auto-discovered via namespace
      end
    end

    initializer "escalated.append_routes" do |app|
      app.routes.append do
        mount Escalated::Engine, at: "/#{Escalated.configuration.route_prefix}"
      end
    end

    initializer "escalated.inertia" do
      ActiveSupport.on_load(:action_controller) do
        # Configure Inertia shared data at engine level
      end
    end

    # Set default plugins_path to Rails.root/lib/escalated/plugins when not
    # explicitly configured. Must run after the host app has booted so
    # Rails.root is available.
    initializer "escalated.plugins_path", after: :load_config_initializers do |app|
      if Escalated.configuration.plugins_path.nil?
        Escalated.configuration.plugins_path = app.root.join("lib", "escalated", "plugins").to_s
      end
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
    end

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot, dir: "spec/factories"
    end
  end
end
