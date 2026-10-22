# frozen_string_literal: true

module Escalated
  module Admin
    # Admin/Settings/PublicTickets: the guest policy, stored in the keys the
    # widget and the guest ticket flow read (escalated-laravel's
    # PublicTicketsSettingsController).
    class PublicTicketsSettingsController < Escalated::ApplicationController
      include Escalated::InertiaForms

      before_action :require_admin!

      MODES = %w[unassigned guest_user prompt_signup].freeze

      def show
        render_page 'Escalated/Admin/Settings/PublicTickets', {
          settings: {
            guest_policy_mode: Escalated::EscalatedSetting.get('guest_policy_mode').presence || 'unassigned',
            guest_policy_user_id: Escalated::EscalatedSetting.get('guest_policy_user_id').to_s.presence,
            guest_policy_signup_url_template: Escalated::EscalatedSetting.get('guest_policy_signup_url_template').to_s
          }
        }
      end

      def update
        mode = params[:guest_policy_mode].to_s
        user_id = params[:guest_policy_user_id].presence
        user_id &&= Integer(user_id.to_s, exception: false)
        template = params[:guest_policy_signup_url_template].to_s.strip

        errors = validation_errors(mode, user_id, template)
        return redirect_back_with_form_errors(errors, escalated.admin_settings_public_tickets_path) if errors.any?

        Escalated::EscalatedSetting.set('guest_policy_mode', mode)
        Escalated::EscalatedSetting.set('guest_policy_user_id', mode == 'guest_user' ? user_id.to_s : '')
        Escalated::EscalatedSetting.set('guest_policy_signup_url_template', mode == 'prompt_signup' ? template : '')

        redirect_back_or_to escalated.admin_settings_public_tickets_path, flash: { success: 'Guest policy updated.' }
      end

      private

      def validation_errors(mode, user_id, template)
        errors = {}
        errors['guest_policy_mode'] = "Choose one of: #{MODES.join(', ')}." unless MODES.include?(mode)
        if params[:guest_policy_user_id].present? && !user_id&.positive?
          errors['guest_policy_user_id'] = 'The user must be a positive whole number.'
        elsif mode == 'guest_user' && user_id.nil?
          errors['guest_policy_user_id'] = 'Choose the user guest tickets are filed under.'
        end
        if template.length > 500
          errors['guest_policy_signup_url_template'] = 'The sign-up URL may not be longer than 500 characters.'
        end
        errors
      end
    end
  end
end
