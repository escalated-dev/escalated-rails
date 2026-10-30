# frozen_string_literal: true

module Escalated
  # The second step after the host's password login (ADR
  # 2026-10-29-configurable-access-features): renders the shared
  # Auth/TwoFactorChallenge page and checks a TOTP or recovery code. 404 while
  # two-factor is switched off.
  class TwoFactorChallengesController < Escalated::ApplicationController
    VERIFY_LIMIT = 5
    VERIFY_WINDOW = 60

    self.escalated_two_factor_route = :challenge

    before_action :ensure_two_factor_enabled!
    before_action :require_staff!
    before_action :throttle_verify!, only: :create

    def show
      if enrolment.nil? || Escalated::Support::TwoFactorSession.passed?(session, escalated_current_user)
        return redirect_to(intended_or_home)
      end

      render_page 'Escalated/Auth/TwoFactorChallenge', {
        action: escalated.two_factor_challenge_url,
        error: flash[:error].to_s
      }
    end

    def create
      return redirect_to(intended_or_home, status: :see_other) if enrolment.nil?

      recovery = params[:recovery_code].to_s
      using_recovery = recovery.strip.present?
      return refuse(using_recovery) unless passes?(using_recovery, recovery)

      intended = Escalated::Support::TwoFactorSession.take_intended(session)
      renew_session
      Escalated::Support::TwoFactorSession.mark_passed(session, escalated_current_user)
      redirect_to(intended || home_path, status: :see_other)
    end

    private

    def enrolment
      @enrolment ||= Escalated::Services::TwoFactorService.confirmed_for(escalated_current_user)
    end

    def passes?(using_recovery, recovery)
      service = Escalated::Services::TwoFactorService.new
      if using_recovery
        recovery.length <= 64 && service.use_recovery_code(enrolment, recovery)
      else
        params[:code].to_s.length <= 16 && service.verify_and_consume(enrolment, params[:code].to_s)
      end
    end

    # A new session id, keeping the session's data (the host's login with it).
    def renew_session
      kept = session.to_hash.except('session_id', '_csrf_token')
      reset_session
      kept.each { |key, value| session[key] = value }
    end

    def refuse(using_recovery)
      Rails.logger.info("[Escalated] Two-factor challenge failed for user #{escalated_current_user.id}")
      field = using_recovery ? :recovery_code : :code
      message = using_recovery ? 'That recovery code is not valid.' : 'That code is not valid.'

      if request.format.json? && request.headers['X-Inertia'].blank?
        render json: { message: message, errors: { field => message } }, status: :unprocessable_content
      else
        redirect_to escalated.two_factor_challenge_path, status: :see_other, inertia: { errors: { field => message } }
      end
    end

    def throttle_verify!
      store = (Escalated.configuration.two_factor || {}).to_h.symbolize_keys[:cache_store] || Rails.cache
      bucket = Time.current.to_i / VERIFY_WINDOW
      key = "escalated:two_factor_verify:#{escalated_current_user&.id || request.remote_ip}:#{bucket}"
      hits = store.increment(key, 1, expires_in: (VERIFY_WINDOW + 5).seconds).to_i
      return if hits <= VERIFY_LIMIT

      response.headers['Retry-After'] = VERIFY_WINDOW.to_s
      render plain: 'Too many attempts. Please try again later.', status: :too_many_requests
    end

    def intended_or_home
      Escalated::Support::TwoFactorSession.take_intended(session) || home_path
    end

    def home_path
      current_user_data&.dig(:is_agent) ? escalated.agent_dashboard_path : escalated.admin_reports_path
    end

    def ensure_two_factor_enabled!
      head :not_found unless Escalated::Support::AccessFeatures.two_factor?
    end
  end
end
