Escalated.configure do |config|
  # ============================================================
  # Hosting Mode
  # ============================================================
  # :self_hosted  - All data in your local database (default)
  # :synced       - Local database + cloud sync
  # :cloud        - All data proxied to Escalated Cloud
  config.mode = :self_hosted

  # ============================================================
  # User Configuration
  # ============================================================
  # Your application's user model class name
  config.user_class = "User"

  # ============================================================
  # Database
  # ============================================================
  # Prefix for all Escalated database tables
  config.table_prefix = "escalated_"

  # ============================================================
  # Routing
  # ============================================================
  # URL prefix for Escalated routes (e.g., /support/tickets)
  config.route_prefix = "support"

  # ============================================================
  # Authentication & Authorization
  # ============================================================
  # Middleware applied to all Escalated routes
  config.middleware = [:authenticate_user!]

  # Additional middleware for admin routes (nil = same as middleware)
  config.admin_middleware = nil

  # ============================================================
  # Ticket Settings
  # ============================================================
  # Allow customers to close their own tickets
  config.allow_customer_close = true

  # Automatically close resolved tickets after N days (nil to disable)
  config.auto_close_resolved_after_days = 7

  # Default priority for new tickets
  config.default_priority = :medium

  # ============================================================
  # Attachments
  # ============================================================
  # Maximum number of attachments per ticket/reply
  config.max_attachments = 5

  # Maximum file size in KB (10 MB default)
  config.max_attachment_size_kb = 10_240

  # ActiveStorage service to use (:local, :amazon, :google, etc.)
  config.storage_service = :local

  # ============================================================
  # SLA Configuration
  # ============================================================
  config.sla = {
    enabled: true,
    business_hours_only: true,
    business_hours: {
      start: 9,
      end: 17,
      timezone: "UTC",
      working_days: [1, 2, 3, 4, 5]  # Monday through Friday
    }
  }

  # ============================================================
  # Notifications
  # ============================================================
  # Available channels: :email
  config.notification_channels = [:email]

  # Webhook URL for external integrations (nil to disable)
  config.webhook_url = nil

  # ============================================================
  # Plugin System
  # ============================================================
  # Enable the plugin system (default: false)
  config.plugins_enabled = false

  # Directory where plugins are installed
  # Defaults to Rails.root.join("plugins/escalated") when nil
  # config.plugins_path = Rails.root.join("plugins", "escalated").to_s

  # ============================================================
  # Cloud Configuration (only for :synced and :cloud modes)
  # ============================================================
  # config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  # config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
