module Escalated
  class Configuration
    attr_accessor :mode,
                  :user_class,
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
                  # REST API settings
                  :api_enabled,
                  :api_rate_limit,
                  :api_token_expiry_days,
                  :api_prefix

    def initialize
      @mode = :self_hosted
      @user_class = "User"
      @table_prefix = "escalated_"
      @route_prefix = "support"
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
          timezone: "UTC",
          working_days: [1, 2, 3, 4, 5]
        }
      }
      @notification_channels = [:email]
      @webhook_url = nil
      @storage_service = :local

      # Inbound email defaults
      @inbound_email_enabled = false
      @inbound_email_adapter = nil  # :mailgun, :postmark, :ses, :imap
      @inbound_email_address = nil  # e.g., "support@yourdomain.com"
      @mailgun_signing_key = nil
      @postmark_inbound_token = nil
      @ses_region = nil
      @ses_topic_arn = nil
      @imap_host = nil
      @imap_port = 993
      @imap_encryption = :ssl
      @imap_username = nil
      @imap_password = nil
      @imap_mailbox = "INBOX"

      # REST API defaults
      @api_enabled = false
      @api_rate_limit = 60
      @api_token_expiry_days = nil
      @api_prefix = "support/api/v1"
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

    def user_model
      user_class.constantize
    end
  end
end
