# frozen_string_literal: true

require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_record/railtie'
require 'active_storage/engine'
require 'action_controller/railtie'
require 'action_mailer/railtie'
require 'action_view/railtie'
require 'action_cable/engine'
require 'rails/test_unit/railtie'

Bundler.require(*Rails.groups)

# Ensure Inertia helpers (e.g. inertia_share) are mixed into ActionController::Base in the dummy app.
require 'inertia_rails'

# Runtime dependencies of the engine are not always auto-required by this minimal dummy app.
require 'pundit'

require 'escalated'

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path('..', __dir__)
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false

    config.action_controller.allow_forgery_protection = false if Rails.env.test?

    # Minimal configuration for testing
    config.active_record.maintain_test_schema = false

    # Configure Active Storage (required for Attachment model)
    config.active_storage.service = :test if config.respond_to?(:active_storage)

    # Action Mailer test config
    config.action_mailer.delivery_method = :test
    config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }
  end
end

# Configure Escalated for testing
Escalated.configure do |config|
  config.mode = :self_hosted
  config.user_class = 'User'
  config.table_prefix = 'escalated_'
  config.route_prefix = 'support'
  config.notification_channels = [] # Disable email notifications in tests
  config.sla = {
    enabled: true,
    business_hours_only: false,
    business_hours: {
      start: 9,
      end: 17,
      timezone: 'UTC',
      working_days: [1, 2, 3, 4, 5]
    }
  }
end
