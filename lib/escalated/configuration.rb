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
                  :storage_service

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
