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

    initializer "escalated.api_routes" do |app|
      # Conditionally load API routes when api_enabled is true.
      # These are mounted directly on the host app (not inside the engine mount)
      # so they can use ActionController::API without CSRF.
      app.routes.append do
        if Escalated.configuration.api_enabled
          scope Escalated.configuration.api_prefix, module: "escalated/api/v1", as: "escalated_api_v1" do
            post "auth/validate", to: "auth#validate"
            get "dashboard", to: "dashboard#index"

            resources :tickets, param: :reference, only: [:index, :show, :create, :destroy] do
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

            get "agents", to: "resources#agents"
            get "departments", to: "resources#departments"
            get "tags", to: "resources#tags"
            get "canned-responses", to: "resources#canned_responses"
            get "macros", to: "resources#macros"
            get "realtime/config", to: "resources#realtime_config"
          end
        end
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
