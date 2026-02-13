module Escalated
  class Engine < ::Rails::Engine
    isolate_namespace Escalated

    initializer "escalated.configuration" do |app|
      # Allow host app to configure Escalated before boot
    end

    initializer 'escalated.i18n' do
      config.i18n.load_path += Dir[root.join('config', 'locales', '*.yml')]
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

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot, dir: "spec/factories"
    end
  end
end
