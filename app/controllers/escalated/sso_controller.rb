# frozen_string_literal: true

module Escalated
  # Sign-in through the SSO provider chosen in Admin > Settings > SSO (ADR
  # 2026-10-29-configurable-access-features). Every route answers 404 unless
  # SSO is switched on and the provider it serves is the chosen one. The routes
  # are for guests: the host's own login stays as it is. Every refusal answers
  # a generic 403 and logs the reason.
  class SsoController < Escalated::ApplicationController
    OAUTH_STATE = 'escalated.sso.oauth_state'
    OAUTH_PKCE = 'escalated.sso.oauth_pkce'
    REFUSED = 'Single sign-on failed. Contact your administrator.'

    # The IdP posts the assertion (and may post the JWT) cross-site: the signed,
    # single-use message is what authenticates the request, not a CSRF token.
    skip_forgery_protection only: %i[saml_acs jwt_callback]

    before_action :ensure_sso_enabled!

    def login
      case sso.provider
      when 'saml' then redirect_to sso.saml_login_url(escalated), allow_other_host: true
      when 'jwt' then redirect_to sso.jwt_login_url(escalated), allow_other_host: true
      when 'oauth' then start_oauth
      else head :not_found
      end
    rescue Escalated::Services::SsoValidationError => e
      refuse(e)
    end

    def metadata
      return head(:not_found) unless sso.provider == 'saml'

      render xml: sso.saml_metadata(escalated), content_type: 'application/samlmetadata+xml'
    end

    def saml_acs
      return head(:not_found) unless sso.provider == 'saml'

      sign_in_with { sso.validate_saml_response(escalated, params[:SAMLResponse].to_s) }
    end

    def oauth_callback
      return head(:not_found) unless sso.provider == 'oauth'

      state = session.delete(OAUTH_STATE).to_s
      verifier = session.delete(OAUTH_PKCE).to_s
      sign_in_with do
        if params[:error].present?
          raise Escalated::Services::SsoValidationError, "OAuth refused: the provider returned #{params[:error]}."
        end
        if state.empty? || !ActiveSupport::SecurityUtils.secure_compare(state, params[:state].to_s)
          raise Escalated::Services::SsoValidationError, 'OAuth refused: missing or mismatched state.'
        end
        if params[:code].blank? || verifier.empty?
          raise Escalated::Services::SsoValidationError, 'OAuth refused: no authorization code or PKCE verifier.'
        end

        sso.oauth_identity(escalated, params[:code].to_s, verifier)
      end
    end

    def jwt_callback
      return head(:not_found) unless sso.provider == 'jwt'

      sign_in_with { sso.validate_jwt(params[:jwt].to_s, main_app.root_url) }
    end

    private

    def sso
      @sso ||= Escalated::Services::SsoService.new
    end

    def ensure_sso_enabled!
      head :not_found unless Escalated::Support::AccessFeatures.sso?
    end

    def start_oauth
      started = sso.oauth_start(escalated)
      session[OAUTH_STATE] = started[:state]
      session[OAUTH_PKCE] = started[:verifier]
      redirect_to started[:url], allow_other_host: true
    end

    def sign_in_with
      user = resolve_user(yield)
      intended = Escalated::Support::TwoFactorSession.take_intended(session)
      sign_in_host(user)
      kept = session.to_hash.except('session_id', '_csrf_token')
      reset_session
      kept.each { |key, value| session[key] = value }
      # A new sign-in passes the two-factor challenge again, SSO or not.
      Escalated::Support::TwoFactorSession.forget(session)
      Rails.logger.info("[Escalated] SSO signed in user #{user.id} through #{sso.provider}")
      redirect_to(intended || home_path)
    rescue Escalated::Services::SsoValidationError => e
      refuse(e)
    end

    # The host user for the identity: matched by email (case-insensitive),
    # created only with sso[:create_users]; the asserted role replaces the
    # user's Escalated roles only with roles & permissions on and
    # sso[:sync_roles]. SSO never grants the host's admin or agent gate.
    def resolve_user(identity)
      model = Escalated.configuration.user_model
      user = model.where('LOWER(email) = ?', identity[:email].downcase).first
      user ||= create_user(model, identity)
      sync_role(user, identity[:role])
      user
    end

    def create_user(model, identity)
      options = Escalated::Services::SsoService
      unless options.truthy?(options.option(:create_users, 'ESCALATED_SSO_CREATE_USERS'))
        raise Escalated::Services::SsoValidationError,
              "SSO refused: no user has the email [#{identity[:email]}] and creating users is off."
      end

      user = model.new(email: identity[:email])
      user.name = identity[:name].presence || identity[:email].split('@').first if user.respond_to?(:name=)
      user.password = SecureRandom.hex(32) if user.respond_to?(:password=)
      user.save!
      user
    end

    def sync_role(user, slug)
      options = Escalated::Services::SsoService
      return if slug.blank? || !Escalated::Support::AccessFeatures.roles_permissions?
      return unless options.truthy?(options.option(:sync_roles, 'ESCALATED_SSO_SYNC_ROLES'))

      role = Escalated::Role.find_by(slug: slug)
      return unless role

      Escalated::Role.joins(:users).where(Escalated.table_name('role_users') => { user_id: user.id }).find_each do |old|
        old.users.delete(user)
      end
      role.users << user
    end

    # Signs the user in on the host: sso[:sign_in] (a callable taking the
    # controller and the user), else Devise's sign_in.
    def sign_in_host(user)
      hook = Escalated::Services::SsoService.options[:sign_in]
      if hook.respond_to?(:call)
        hook.call(self, user)
      elsif respond_to?(:sign_in, true)
        sign_in(user)
      else
        raise Escalated::Services::SsoValidationError,
              'SSO refused: the host provides no sign-in (config.sso[:sign_in] or Devise).'
      end
    end

    def home_path
      Escalated::Services::SsoService.option(:redirect_to, 'ESCALATED_SSO_REDIRECT_TO').presence ||
        escalated.agent_dashboard_path
    end

    def refuse(error)
      Rails.logger.warn("[Escalated] #{error.message}")
      render plain: REFUSED, status: :forbidden
    end
  end
end
