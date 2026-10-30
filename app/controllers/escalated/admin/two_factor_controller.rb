# frozen_string_literal: true

module Escalated
  module Admin
    # Two-factor enrolment (Admin/Settings/TwoFactor), ADR
    # 2026-10-29-configurable-access-features. It is about the signed-in
    # user's own account, so every staff user reaches it, not only admins, and
    # it needs no permission. 404 while two-factor is switched off.
    class TwoFactorController < Escalated::ApplicationController
      self.escalated_two_factor_route = :enrolment

      before_action :ensure_two_factor_enabled!
      before_action :require_staff!

      def show
        two_factor = Escalated::TwoFactor.find_by(user_id: escalated_current_user.id)

        render_page 'Escalated/Admin/Settings/TwoFactor', {
          enabled: two_factor&.confirmed? || false,
          pending: two_factor.present? && !two_factor.confirmed?,
          required: Escalated::Services::TwoFactorService.required?
        }
      end

      # Starts enrolment. The page reads the QR code and recovery codes from the
      # flash; the secret itself stays on the server until a code proves the
      # user's authenticator has it.
      def setup
        if Escalated::Services::TwoFactorService.confirmed_for(escalated_current_user)
          return redirect_back_or_to(escalated.admin_settings_two_factor_path,
                                     alert: I18n.t('escalated.admin.two_factor.already_enabled',
                                                   default: 'Two-factor authentication is already enabled.'))
        end

        Escalated::TwoFactor.where(user_id: escalated_current_user.id, confirmed_at: nil).delete_all

        totp = Escalated::Services::TwoFactorService.new
        secret = totp.generate_secret
        recovery_codes = totp.generate_recovery_codes
        Escalated::TwoFactor.create!(user_id: escalated_current_user.id, secret: secret, recovery_codes: recovery_codes)

        flash[:two_factor_setup] = {
          qr_uri: totp.generate_qr_uri(secret, escalated_current_user.email),
          recovery_codes: recovery_codes
        }
        redirect_back_or_to escalated.admin_settings_two_factor_path
      end

      def confirm
        two_factor = Escalated::TwoFactor.find_by(user_id: escalated_current_user.id, confirmed_at: nil)
        service = Escalated::Services::TwoFactorService.new

        unless two_factor && service.verify_and_consume(two_factor, params[:code].to_s)
          return redirect_back_or_to(escalated.admin_settings_two_factor_path,
                                     alert: I18n.t('escalated.admin.two_factor.invalid_code'),
                                     inertia: { errors: { code: 'Invalid verification code.' } })
        end

        two_factor.update!(confirmed_at: Time.current)
        # The code just entered proves the second factor for this session.
        Escalated::Support::TwoFactorSession.mark_passed(session, escalated_current_user)

        flash[:two_factor_confirmed] = { recovery_codes: two_factor.recovery_codes }
        redirect_back_or_to escalated.admin_settings_two_factor_path,
                            notice: I18n.t('escalated.admin.two_factor.enabled')
      end

      def disable
        Escalated::TwoFactor.where(user_id: escalated_current_user.id).delete_all

        redirect_to escalated.admin_settings_two_factor_path, notice: I18n.t('escalated.admin.two_factor.disabled')
      end

      private

      def ensure_two_factor_enabled!
        head :not_found unless Escalated::Support::AccessFeatures.two_factor?
      end
    end
  end
end
