# frozen_string_literal: true

module Escalated
  module Admin
    class SettingsController < Escalated::ApplicationController
      before_action :require_admin!

      SENSITIVE_KEYS = %w[mailgun_signing_key postmark_inbound_token imap_password].freeze
      SSO_SECRET_KEYS = %w[sso_jwt_secret].freeze

      def index
        settings = Escalated::EscalatedSetting.all_as_hash
        SENSITIVE_KEYS.each do |key|
          settings[key] = Escalated::Support::SecretMask.mask(settings[key]) if settings.key?(key)
        end

        render_page 'Escalated/Admin/Settings', {
          settings: settings
        }
      end

      # The SSO settings screen, showing the settings SsoService actually reads.
      #
      # It used to show a different, OIDC-shaped set -- sso_client_id and
      # sso_issuer -- which SsoService has never consulted, and none of the keys
      # it does consult. So the form saved values nothing used and hid the ones
      # that mattered, and it rendered under a page name the frontend does not
      # ship, which meant the whole screen came up blank anyway.
      #
      # Stored secrets reach the page only as a mask ('' when unset).
      def sso
        settings = sso_service.get_config
        SSO_SECRET_KEYS.each { |key| settings[key] = Escalated::Support::SecretMask.mask(settings[key]) }

        render_page 'Escalated/Admin/Settings/SsoSettings', {
          settings: settings
        }
      end

      def update_sso
        data = params.permit(*Escalated::Services::SsoService::CONFIG_KEYS).to_h
        # The page posts the mask back for a secret the admin did not change.
        SSO_SECRET_KEYS.each { |key| data.delete(key) if Escalated::Support::SecretMask.masked?(data[key]) }
        sso_service.save_config(data)

        redirect_to escalated.admin_settings_sso_path, notice: I18n.t('escalated.admin.settings.updated')
      rescue Escalated::Services::SsoValidationError => e
        redirect_to escalated.admin_settings_sso_path, alert: e.message
      end

      def update
        # Validated before anything is saved, so a bad entry changes nothing.
        origins_error = widget_allowed_origins_error
        if origins_error
          errors = { widget_allowed_origins: origins_error }
          return redirect_to(escalated.admin_settings_path, alert: origins_error, inertia: { errors: errors })
        end

        update_widget_settings

        # Boolean settings, each written only when the form sends it: a page
        # that posts one switch (Admin/Settings/TwoFactor's "require for all
        # staff") must not turn the others off.
        boolean_settings.each do |key|
          next unless params.key?(key)

          value = params[key].to_s.in?(%w[1 true on]) ? '1' : '0'
          Escalated::EscalatedSetting.set(key, value)
        end

        # Only written when the form sends it, so an older settings form that
        # has no Live Chat switch does not turn chat off.
        if params.key?(:chat_enabled)
          Escalated::EscalatedSetting.set('chat_enabled', params[:chat_enabled].in?(%w[1 true on]) ? '1' : '0')
        end

        # Integer settings
        %w[auto_close_resolved_after_days max_attachments_per_reply max_attachment_size_kb].each do |key|
          raw = params[key]
          next if raw.blank?

          int_val = raw.to_i
          Escalated::EscalatedSetting.set(key, [0, int_val].max.to_s) if int_val >= 0
        end

        # String settings
        prefix = params[:ticket_reference_prefix].to_s.strip
        if prefix.present? && prefix.match?(/\A[a-zA-Z0-9]+\z/) && prefix.length <= 10
          Escalated::EscalatedSetting.set('ticket_reference_prefix', prefix)
        end

        # Inbound email settings
        update_inbound_email_settings

        redirect_to escalated.admin_settings_path, notice: I18n.t('escalated.admin.settings.updated')
      end

      private

      BOOLEAN_SETTINGS = %w[guest_tickets_enabled allow_customer_close inbound_email_enabled show_powered_by
                            knowledge_base_enabled knowledge_base_public knowledge_base_feedback_enabled].freeze

      # two_factor_required only while two-factor is switched on.
      def boolean_settings
        return BOOLEAN_SETTINGS unless Escalated::Support::AccessFeatures.two_factor?

        BOOLEAN_SETTINGS + %w[two_factor_required]
      end

      WIDGET_POSITIONS = %w[bottom-right bottom-left].freeze

      # The entries in widget_allowed_origins that are not bare origins, as a
      # message, or nil when every entry is valid (or the field was not sent).
      def widget_allowed_origins_error
        return nil unless params.key?(:widget_allowed_origins)

        invalid = widget_origin_entries.reject { |entry| Escalated::Support::WidgetOrigins.normalize_pattern(entry) }
        return nil if invalid.empty?

        "Not a site origin (scheme://host[:port]): #{invalid.join(', ')}"
      end

      def widget_origin_entries
        params[:widget_allowed_origins].to_s.split(/[\s,]+/).reject(&:empty?)
      end

      # The Support Widget section of the settings screen. Each key is saved only
      # when the form sends it, so other forms posting here leave it alone.
      def update_widget_settings
        if params.key?(:widget_allowed_origins)
          Escalated::EscalatedSetting.set('widget_allowed_origins', widget_origin_entries.join("\n"))
        end
        if params.key?(:widget_enabled)
          enabled = params[:widget_enabled].to_s.in?(%w[1 true on])
          Escalated::EscalatedSetting.set('widget_enabled', enabled ? '1' : '0')
        end
        color = params[:widget_color].to_s.strip
        Escalated::EscalatedSetting.set('widget_color', color) if color.match?(/\A#\h{3}(\h{3})?\z/)
        position = params[:widget_position].to_s
        Escalated::EscalatedSetting.set('widget_position', position) if WIDGET_POSITIONS.include?(position)
        return unless params.key?(:widget_greeting)

        Escalated::EscalatedSetting.set('widget_greeting', params[:widget_greeting].to_s.strip[0, 255])
      end

      def update_inbound_email_settings
        # Adapter selection (mailgun, postmark, ses, imap)
        adapter = params[:inbound_email_adapter].to_s.strip.downcase
        if adapter.present? && %w[mailgun postmark ses imap].include?(adapter)
          Escalated::EscalatedSetting.set('inbound_email_adapter', adapter)
        end

        # Inbound email address
        address = params[:inbound_email_address].to_s.strip
        if address.present? && address.match?(/\A[^@\s]+@[^@\s]+\z/)
          Escalated::EscalatedSetting.set('inbound_email_address', address)
        elsif params.key?(:inbound_email_address) && address.blank?
          Escalated::EscalatedSetting.set('inbound_email_address', '')
        end

        # Adapter-specific string settings (only save if present, skip masked values)
        %w[
          mailgun_signing_key postmark_inbound_token
          ses_region ses_topic_arn
          imap_host imap_username imap_password imap_mailbox
        ].each do |key|
          next unless params.key?(key)

          raw = params[key].to_s.strip
          next if SENSITIVE_KEYS.include?(key) && Escalated::Support::SecretMask.masked?(raw)

          Escalated::EscalatedSetting.set(key, raw)
        end

        # IMAP port (integer)
        if params[:imap_port].present?
          port = params[:imap_port].to_i
          Escalated::EscalatedSetting.set('imap_port', port.to_s) if port.positive? && port <= 65_535
        end

        # IMAP encryption (ssl, tls, starttls, none)
        encryption = params[:imap_encryption].to_s.strip.downcase
        return unless encryption.present? && %w[ssl tls starttls none].include?(encryption)

        Escalated::EscalatedSetting.set('imap_encryption', encryption)
      end

      def sso_service
        @sso_service ||= Escalated::Services::SsoService.new
      end

      def admin_settings_path
        "/#{Escalated.configuration.route_prefix}/admin/settings"
      end
    end
  end
end
