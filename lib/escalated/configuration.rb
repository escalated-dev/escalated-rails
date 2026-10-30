# frozen_string_literal: true

module Escalated
  class Configuration
    GUEST_RATE_LIMIT_DEFAULTS = {
      enabled: true,
      tickets_per_minute: 5,
      replies_per_minute: 10,
      # Every mobile guest route (docs/guest-access.md "Mobile guest API").
      requests_per_minute: 60,
      cache_store: nil
    }.freeze

    attr_accessor :mode,
                  :visibility,
                  :accounts,
                  :user_class,
                  :user_id_type,
                  :table_prefix,
                  :database_connection,
                  :route_prefix,
                  # Entries merged over the built-in route list (Escalated::RouteList)
                  # the frontend's route(name, params) resolves against:
                  # { 'login' => '/users/sign_in', name => { uri:, methods: } }.
                  :route_overrides,
                  :middleware,
                  :admin_middleware,
                  :hosted_api_url,
                  :hosted_api_key,
                  :hosted_signing_secret,
                  :allow_customer_close,
                  :auto_close_resolved_after_days,
                  :max_attachments,
                  :max_attachment_size_kb,
                  :attachment_download_ttl_minutes,
                  :default_priority,
                  :sla,
                  :notification_channels,
                  :webhook_url,
                  # Key for the X-Escalated-Signature on requests to webhook_url
                  :webhook_secret,
                  # Let admin webhooks and workflow send_webhook actions reach
                  # loopback, private and link-local addresses
                  :allow_private_webhook_urls,
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
                  # Per-client-IP limits on the guest ticket and reply endpoints
                  :guest_rate_limit,
                  # Verified guest access (docs/guest-access.md)
                  :guest_access_ttl_minutes,
                  :guest_codes_per_client_per_hour,
                  :guest_codes_per_mailbox_per_hour,
                  :accept_legacy_guest_tokens,
                  # Sites that may embed the widget (docs/embedding-the-widget.md)
                  :widget_allowed_origins,
                  :widget_preflight_max_age,
                  :widget_serve_script,
                  :api_token_expiry_days,
                  :api_prefix,
                  # Branding (used by newsletters + emails)
                  :app_name,
                  :app_url,
                  # Sender address for ticket emails, e.g. "Support <help@example.com>"
                  :mailer_from,
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
                  :ticket_subject_types,
                  # Host-app authentication callbacks for the general JSON API
                  # auth endpoints (login/register/refresh/profile/logout).
                  # Each is a callable; nil means the endpoint responds 501.
                  # Escalated owns no credentials, so it ships no password hasher.
                  :api_authenticator,
                  :api_registrar,
                  :api_token_refresher,
                  :api_profile_updater,
                  :api_logout,
                  # Install-level access switches (ADR 2026-10-29): a hash of
                  # roles_permissions / two_factor / sso booleans. Unset keys fall
                  # back to ESCALATED_ROLES_PERMISSIONS / _TWO_FACTOR / _SSO, else off.
                  :access,
                  # Two-factor settings used while access[:two_factor] is on:
                  # { required:, issuer:, cache_store: } (env ESCALATED_TWO_FACTOR_REQUIRED,
                  # ESCALATED_TWO_FACTOR_ISSUER). cache_store counts verify attempts.
                  :two_factor,
                  # Single sign-on, used while access[:sso] is on: { sp_entity_id:,
                  # allow_idp_initiated:, jwt_audience:, clock_skew:, create_users:,
                  # sync_roles:, redirect_to:, sign_in: } (ESCALATED_SSO_* env fallbacks).
                  :sso

    def initialize
      @mode = :self_hosted
      @visibility = 'all'
      @accounts = { enabled: false, scope_agents: false, resolver: nil }
      @user_class = 'User'
      @user_id_type = :auto
      @table_prefix = 'escalated_'
      @database_connection = nil
      @route_prefix = 'support'
      @route_overrides = {}
      @middleware = [:authenticate_user!]
      @admin_middleware = nil
      @hosted_api_url = nil
      @hosted_api_key = nil
      @hosted_signing_secret = nil
      @allow_customer_close = true
      @auto_close_resolved_after_days = 7
      @max_attachments = 5
      @max_attachment_size_kb = 10_240
      # How long a signed attachment download link lives (1 to 60 minutes).
      @attachment_download_ttl_minutes = 10
      @default_priority = :medium
      @sla = {
        enabled: true,
        targeted: false,
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
      @webhook_secret = nil
      @allow_private_webhook_urls = false
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

      # Per-client-IP limits on the unauthenticated guest endpoints (widget and
      # guest-form ticket submission, guest replies). Over the limit: 429 with
      # Retry-After. Tickets and replies are counted separately over 60 seconds.
      # Keys the host sets are merged over these defaults.
      #   enabled: set false only when the host already throttles upstream.
      #   cache_store: an ActiveSupport::Cache::Store for the counters; nil uses
      #     Rails.cache. Use a shared store (Redis, Memcache, Solid Cache) when
      #     running several processes.
      # The client IP is request.remote_ip. Behind a proxy or load balancer,
      # set config.action_dispatch.trusted_proxies, or every guest shares the
      # proxy's address.
      @guest_rate_limit = GUEST_RATE_LIMIT_DEFAULTS.dup

      # Origins (scheme://host[:port], or https://*.example.com) whose pages may
      # call the widget routes cross-origin. Combined with the
      # widget_allowed_origins admin setting. Empty: no cross-origin access.
      # How long a guest grant lives, clamped to 5 minutes .. 7 days.
      @guest_access_ttl_minutes = 1440
      @guest_codes_per_client_per_hour = 3
      @guest_codes_per_mailbox_per_hour = 10
      # Permanent guest_token links from before verified access keep working
      # until a grant is issued for the ticket. Turn off to retire them all.
      @accept_legacy_guest_tokens = true
      @widget_allowed_origins = ENV.fetch('ESCALATED_WIDGET_ALLOWED_ORIGINS', '').split(',').map(&:strip)
                                   .reject(&:empty?)
      @widget_preflight_max_age = 600
      # Mount {route_prefix}/widget/embed.js, the standalone widget bundle.
      @widget_serve_script = true

      # Branding defaults
      @app_name = 'Support'
      @app_url = nil
      @mailer_from = nil

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

      # API auth callbacks (host-provided; nil → endpoint responds 501)
      @api_authenticator = nil
      @api_registrar = nil
      @api_token_refresher = nil
      @api_profile_updater = nil
      @api_logout = nil
      @access = {}
      @two_factor = {}
      @sso = {}
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

    # guest_rate_limit with any key the host left out filled from the defaults.
    def guest_rate_limit_settings
      GUEST_RATE_LIMIT_DEFAULTS.merge((guest_rate_limit || {}).to_h.symbolize_keys)
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
