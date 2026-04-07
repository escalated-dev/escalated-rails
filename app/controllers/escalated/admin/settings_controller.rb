# frozen_string_literal: true

module Escalated
  module Admin
    class SettingsController < Escalated::ApplicationController
      before_action :require_admin!

      SENSITIVE_KEYS = %w[mailgun_signing_key postmark_inbound_token imap_password].freeze

      def index
        settings = Escalated::EscalatedSetting.all_as_hash
        SENSITIVE_KEYS.each do |key|
          settings[key] = mask_secret(settings[key]) if settings.key?(key)
        end

        render_page 'Escalated/Admin/Settings', {
          settings: settings
        }
      end

      def two_factor
        render_page 'Escalated/Admin/Settings/TwoFactor', {
          two_factor_required: Escalated::EscalatedSetting.get('two_factor_required') == '1',
          two_factor_grace_period_hours: Escalated::EscalatedSetting.get('two_factor_grace_period_hours').to_i
        }
      end

      def two_factor_setup
        render_page 'Escalated/Admin/Settings/TwoFactorSetup', {
          otp_secret: ROTP::Base32.random,
          user_email: escalated_current_user.email
        }
      end

      def two_factor_confirm
        totp = ROTP::TOTP.new(params[:otp_secret])

        unless totp.verify(params[:otp_code].to_s, drift_behind: 30)
          return redirect_back_or_to(escalated.admin_settings_two_factor_path,
                                     alert: I18n.t('escalated.admin.two_factor.invalid_code'))
        end

        Escalated::TwoFactor.create_or_update_for(
          escalated_current_user,
          otp_secret: params[:otp_secret]
        )

        redirect_to escalated.admin_settings_two_factor_path, notice: I18n.t('escalated.admin.two_factor.enabled')
      end

      def two_factor_disable
        two_factor = Escalated::TwoFactor.find_by(user_id: escalated_current_user.id)
        two_factor&.destroy!

        redirect_to escalated.admin_settings_two_factor_path, notice: I18n.t('escalated.admin.two_factor.disabled')
      end

      def sso
        render_page 'Escalated/Admin/Settings/Sso', {
          sso_enabled: Escalated::EscalatedSetting.get('sso_enabled') == '1',
          sso_provider: Escalated::EscalatedSetting.get('sso_provider'),
          sso_metadata_url: Escalated::EscalatedSetting.get('sso_metadata_url'),
          sso_client_id: Escalated::EscalatedSetting.get('sso_client_id'),
          sso_issuer: Escalated::EscalatedSetting.get('sso_issuer')
        }
      end

      def update_sso
        %w[sso_provider sso_metadata_url sso_client_id sso_issuer sso_client_secret].each do |key|
          next unless params.key?(key)

          Escalated::EscalatedSetting.set(key, params[key].to_s.strip)
        end

        sso_enabled = params[:sso_enabled].in?(%w[1 true on]) ? '1' : '0'
        Escalated::EscalatedSetting.set('sso_enabled', sso_enabled)

        redirect_to escalated.admin_settings_sso_path, notice: I18n.t('escalated.admin.settings.updated')
      end

      def csat
        render_page 'Escalated/Admin/Settings/Csat', {
          csat_enabled: Escalated::EscalatedSetting.get('csat_enabled') == '1',
          csat_send_after_hours: Escalated::EscalatedSetting.get('csat_send_after_hours').to_i,
          csat_message: Escalated::EscalatedSetting.get('csat_message')
        }
      end

      def update_csat
        csat_enabled = params[:csat_enabled].in?(%w[1 true on]) ? '1' : '0'
        Escalated::EscalatedSetting.set('csat_enabled', csat_enabled)

        if params[:csat_send_after_hours].present?
          hours = params[:csat_send_after_hours].to_i
          Escalated::EscalatedSetting.set('csat_send_after_hours', [0, hours].max.to_s)
        end

        if params[:csat_message].present?
          Escalated::EscalatedSetting.set('csat_message', params[:csat_message].to_s.strip)
        end

        redirect_to escalated.admin_settings_csat_path, notice: I18n.t('escalated.admin.settings.updated')
      end

      def update
        # Boolean settings
        %w[guest_tickets_enabled allow_customer_close inbound_email_enabled show_powered_by].each do |key|
          value = params[key].in?(%w[1 true on]) ? '1' : '0'
          Escalated::EscalatedSetting.set(key, value)
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
          next if SENSITIVE_KEYS.include?(key) && masked_value?(raw)

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

      def mask_secret(value)
        return '' if value.blank?

        len = value.length
        return '*' * len if len <= 6

        value[0, 3] + ('*' * [len - 3, 12].min)
      end

      def masked_value?(value)
        return false if value.blank?

        value.match?(/\A.{0,3}\*{3,}\z/)
      end

      def admin_settings_path
        "/#{Escalated.configuration.route_prefix}/admin/settings"
      end
    end
  end
end
