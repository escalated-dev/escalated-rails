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
        %w[guest_tickets_enabled allow_customer_close].each do |key|
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

        redirect_to escalated.admin_settings_path, notice: "Settings updated successfully."
      end

      private

      def admin_settings_path
        "/#{Escalated.configuration.route_prefix}/admin/settings"
      end
    end
  end
end
