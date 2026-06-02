# frozen_string_literal: true

module Escalated
  class Configuration
    attr_accessor :mode,
                  :user_class,
                  :user_id_type,
                  :table_prefix,
                  :route_prefix,
                  :middleware,
                  :admin_middleware,
                  :hosted_api_url,
                  :hosted_api_key,
                  :allow_customer_close,
                  :auto_close_resolved_after_days,
                  :max_attachments,
                  :max_attachment_size_kb,
                  :default_priority,
                  :sla,
                  :notification_channels,
                  :webhook_url,
                  :storage_service,
                  # Plugin system (Ruby-based)
                  :plugins_enabled,
                  :plugins_path,
                  # SDK plugin bridge (Node.js runtime)
                  :sdk_plugins_enabled,
                  :plugin_runtime_command,
                  :plugin_runtime_cwd,
                  # Email (outbound + inbound threading)
                  :email_domain,
                  :email_inbound_secret,
                  # Inbound email settings
                  :inbound_email_enabled,
                  :inbound_email_adapter,
                  :inbound_email_address,
                  # Mailgun
                  :mailgun_signing_key,
                  # Postmark
                  :postmark_inbound_token,
                  # AWS SES
                  :ses_region,
                  :ses_topic_arn,
                  # IMAP
                  :imap_host,
                  :imap_port,
                  :imap_encryption,
                  :imap_username,
                  :imap_password,
                  :imap_mailbox,
                  # UI settings
                  :ui_enabled,
                  # REST API settings
                  :api_enabled,
                  :api_rate_limit,
                  :api_token_expiry_days,
                  :api_prefix,
                  # Branding (used by newsletters + emails)
                  :app_name,
                  :app_url,
                  # Newsletters (optional, disabled by default)
                  :enable_newsletters,
                  :newsletter_default_from,
                  :newsletter_default_reply_to,
                  :newsletter_default_theme,
                  :newsletter_rate_limit_per_minute,
                  :newsletter_batch_size,
                  :newsletter_tracking_enabled,
                  :newsletter_auto_pause_bounce_rate,
                  :newsletter_auto_pause_threshold,
                  :newsletter_claim_timeout_minutes,
                  :newsletter_themes_dir,
                  :newsletter_markdown_renderer,
                  :newsletter_brand_accent,
                  :newsletter_brand_logo_url,
                  :newsletter_brand_physical_address,
                  # Host-defined custom ticket actions
                  :ticket_actions,
                  # Host models a ticket can be about (Project, Customer, …)
                  :ticket_subject_types

    def initialize
      @mode = :self_hosted
      @user_class = 'User'
      @user_id_type = :auto
      @table_prefix = 'escalated_'
      @route_prefix = 'support'
      @middleware = [:authenticate_user!]
      @admin_middleware = nil
      @hosted_api_url = nil
      @hosted_api_key = nil
      @allow_customer_close = true
      @auto_close_resolved_after_days = 7
      @max_attachments = 5
      @max_attachment_size_kb = 10_240
      @default_priority = :medium
      @sla = {
        enabled: true,
        business_hours_only: true,
        business_hours: {
          start: 9,
          end: 17,
          timezone: 'UTC',
          working_days: [1, 2, 3, 4, 5]
        }
      }
      @notification_channels = [:email]
      @webhook_url = nil
      @storage_service = :local

      # Plugin system defaults
      @plugins_enabled = false
      @plugins_path = nil # Set at boot time if nil (defaults to Rails.root.join("lib/escalated/plugins"))

      # SDK plugin bridge defaults
      @sdk_plugins_enabled    = false
      @plugin_runtime_command = nil  # defaults to "node node_modules/@escalated-dev/plugin-runtime/dist/index.js"
      @plugin_runtime_cwd     = nil  # defaults to Rails.root

      # Email threading — domain for Message-IDs, secret for Reply-To HMAC.
      @email_domain = @email_inbound_secret = nil

      # Inbound email defaults
      @inbound_email_enabled = false
      @inbound_email_adapter = nil  # :mailgun, :postmark, :ses, :imap
      @inbound_email_address = nil  # e.g., "support@yourdomain.com"
      @mailgun_signing_key = nil
      @postmark_inbound_token = nil
      @ses_region = @ses_topic_arn = nil
      @imap_host = nil
      @imap_port = 993
      @imap_encryption = :ssl
      @imap_username = nil
      @imap_password = nil
      @imap_mailbox = 'INBOX'

      # UI defaults
      @ui_enabled = true

      # REST API defaults
      @api_enabled = false
      @api_rate_limit = 60
      @api_token_expiry_days = nil
      @api_prefix = 'support/api/v1'

      # Branding defaults
      @app_name = 'Support'
      @app_url = nil

      # Newsletter defaults (feature off by default)
      @enable_newsletters = false
      @newsletter_default_from = nil
      @newsletter_default_reply_to = nil
      @newsletter_default_theme = 'default'
      @newsletter_rate_limit_per_minute = 60
      @newsletter_batch_size = 50
      @newsletter_tracking_enabled = true
      @newsletter_auto_pause_bounce_rate = 0.05
      @newsletter_auto_pause_threshold = 100
      @newsletter_claim_timeout_minutes = 10
      @newsletter_themes_dir = nil
      @newsletter_markdown_renderer = nil
      @newsletter_brand_accent = '#2563eb'
      @newsletter_brand_logo_url = nil
      @newsletter_brand_physical_address = nil
      @ticket_actions = []
      @ticket_subject_types = []
    end

    def self_hosted?
      mode == :self_hosted
    end

    def synced?
      mode == :synced
    end

    def cloud?
      mode == :cloud
    end

    def sla_enabled?
      sla[:enabled] == true
    end

    def business_hours_only?
      sla[:business_hours_only] == true
    end

    def business_hours
      sla[:business_hours] || {}
    end

    def enable_newsletters?
      @enable_newsletters == true
    end

    def newsletter_tracking_enabled?
      @newsletter_tracking_enabled != false
    end

    def ui_enabled?
      ui_enabled == true
    end

    def plugins_enabled?
      plugins_enabled == true
    end

    def user_model
      user_class.constantize
    end
  end
end
