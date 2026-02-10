require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

require "escalated"

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false

    # Minimal configuration for testing
    config.active_record.maintain_test_schema = false

    # Configure Active Storage (required for Attachment model)
    config.active_storage.service = :test if config.respond_to?(:active_storage)

    # Action Mailer test config
    config.action_mailer.delivery_method = :test
    config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
  end
end

# Configure Escalated for testing
Escalated.configure do |config|
  config.mode = :self_hosted
  config.user_class = "User"
  config.table_prefix = "escalated_"
  config.route_prefix = "support"
  config.notification_channels = [] # Disable email notifications in tests
  config.sla = {
    enabled: true,
    business_hours_only: false,
    business_hours: {
      start: 9,
      end: 17,
      timezone: "UTC",
      working_days: [1, 2, 3, 4, 5]
    }
  }
end
