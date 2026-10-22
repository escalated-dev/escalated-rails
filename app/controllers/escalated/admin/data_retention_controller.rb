# frozen_string_literal: true

module Escalated
  module Admin
    # Admin/Settings/DataRetention (escalated-laravel's DataRetentionController).
    # The settings saved here are applied by Escalated::PurgeExpiredDataJob,
    # also runnable as `rake escalated:purge_expired`.
    class DataRetentionController < Escalated::ApplicationController
      include Escalated::InertiaForms

      before_action :require_admin!

      BOOLEANS = { true => '1', 'true' => '1', '1' => '1', 1 => '1',
                   false => '0', 'false' => '0', '0' => '0', 0 => '0' }.freeze

      def show
        render_page 'Escalated/Admin/Settings/DataRetention', {
          settings: retention.settings,
          purgePreview: retention.preview
        }
      end

      def update
        allowed_periods = Escalated::Services::DataRetentionService::SETTINGS
        periods = allowed_periods.keys.index_with { |key| params[key].to_s }
        gdpr = BOOLEANS[params[:retention_user_data_gdpr]]

        errors = allowed_periods.each_with_object({}) do |(key, allowed), found|
          found[key] = "Choose one of: #{allowed.join(', ')}." unless allowed.include?(periods[key])
        end
        errors['retention_user_data_gdpr'] = 'This must be true or false.' if gdpr.nil?
        return redirect_back_with_form_errors(errors, escalated.admin_settings_data_retention_path) if errors.any?

        periods.each { |key, value| Escalated::EscalatedSetting.set(key, value) }
        Escalated::EscalatedSetting.set(Escalated::Services::DataRetentionService::GDPR_SETTING, gdpr)

        redirect_back_or_to escalated.admin_settings_data_retention_path,
                            flash: { success: 'Data retention settings updated.' }
      end

      private

      def retention
        @retention ||= Escalated::Services::DataRetentionService.new
      end
    end
  end
end
