module Escalated
  module Admin
    class SettingsController < Escalated::ApplicationController
      before_action :require_admin!

      def index
        render inertia: "Escalated/Admin/Settings", props: {
          settings: Escalated::EscalatedSetting.all_as_hash
        }
      end

      def update
        # Boolean settings
        %w[guest_tickets_enabled allow_customer_close inbound_email_enabled].each do |key|
          value = params[key].in?(%w[1 true on]) ? "1" : "0"
          Escalated::EscalatedSetting.set(key, value)
        end

        # Integer settings
        %w[auto_close_resolved_after_days max_attachments_per_reply max_attachment_size_kb].each do |key|
          raw = params[key]
          next unless raw.present?

          int_val = raw.to_i
          Escalated::EscalatedSetting.set(key, [0, int_val].max.to_s) if int_val >= 0
        end

        # String settings
        prefix = params[:ticket_reference_prefix].to_s.strip
        if prefix.present? && prefix.match?(/\A[a-zA-Z0-9]+\z/) && prefix.length <= 10
          Escalated::EscalatedSetting.set("ticket_reference_prefix", prefix)
        end

        # Inbound email settings
        update_inbound_email_settings

        redirect_to escalated.admin_settings_path, notice: "Settings updated successfully."
      end

      private

      def update_inbound_email_settings
        # Adapter selection (mailgun, postmark, ses, imap)
        adapter = params[:inbound_email_adapter].to_s.strip.downcase
        if adapter.present? && %w[mailgun postmark ses imap].include?(adapter)
          Escalated::EscalatedSetting.set("inbound_email_adapter", adapter)
        end

        # Inbound email address
        address = params[:inbound_email_address].to_s.strip
        if address.present? && address.match?(/\A[^@\s]+@[^@\s]+\z/)
          Escalated::EscalatedSetting.set("inbound_email_address", address)
        elsif params.key?(:inbound_email_address) && address.blank?
          Escalated::EscalatedSetting.set("inbound_email_address", "")
        end

        # Adapter-specific string settings (only save if present)
        %w[
          mailgun_signing_key postmark_inbound_token
          ses_region ses_topic_arn
          imap_host imap_username imap_password imap_mailbox
        ].each do |key|
          raw = params[key].to_s.strip
          Escalated::EscalatedSetting.set(key, raw) if params.key?(key)
        end

        # IMAP port (integer)
        if params[:imap_port].present?
          port = params[:imap_port].to_i
          Escalated::EscalatedSetting.set("imap_port", port.to_s) if port > 0 && port <= 65535
        end

        # IMAP encryption (ssl, tls, starttls, none)
        encryption = params[:imap_encryption].to_s.strip.downcase
        if encryption.present? && %w[ssl tls starttls none].include?(encryption)
          Escalated::EscalatedSetting.set("imap_encryption", encryption)
        end
      end

      def admin_settings_path
        "/#{Escalated.configuration.route_prefix}/admin/settings"
      end
    end
  end
end
