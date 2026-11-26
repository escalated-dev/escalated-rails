# frozen_string_literal: true

module Escalated
  # Bearer-token authentication for the staff API, matching escalated-laravel's
  # AuthenticateApiToken. Abilities are `agent`, `admin` and `*`; they are not
  # hierarchical, so an `admin` token cannot call agent endpoints. The owner is
  # re-checked on every request: agent endpoints need an owner who is still an
  # agent (or admin), admin endpoints one who is still an admin.
  #
  # A controller names the ability an action needs by overriding
  # `required_api_ability` (default `agent`); nil means any valid token.
  module ApiAuthentication
    extend ActiveSupport::Concern

    STAFF_ABILITIES = %w[agent admin].freeze

    included do
      attr_reader :current_api_user, :current_api_token
    end

    private

    def authenticate_api_token!
      plain_text = extract_bearer_token
      return render_api_auth_error('Unauthenticated.', :unauthorized) unless plain_text

      # rubocop:disable-next Rails/DynamicFindBy
      api_token = Escalated::ApiToken.find_by_plain_text(plain_text)
      return render_api_auth_error('Invalid token.', :unauthorized) unless api_token
      return render_api_auth_error('Token has expired.', :unauthorized) if api_token.expired?

      ability = required_api_ability
      return render_api_auth_error('Insufficient permissions.', :forbidden) unless api_ability?(api_token, ability)

      user = api_token.tokenable
      return render_api_auth_error('Token owner not found.', :unauthorized) unless user

      refusal = api_owner_refusal(user, ability)
      return render_api_auth_error(refusal, :forbidden) if refusal

      # Record usage
      api_token.update_columns(
        last_used_at: Time.current,
        last_used_ip: request.remote_ip
      )

      @current_api_user = user
      @current_api_token = api_token
    end

    # The ability the current action needs. Staff endpoints default to agent.
    def required_api_ability
      'agent'
    end

    def api_ability?(api_token, ability)
      ability.nil? || api_token.has_ability?(ability)
    end

    # Why the token's owner may not use an agent or admin endpoint, or nil.
    def api_owner_refusal(user, ability)
      return nil unless STAFF_ABILITIES.include?(ability)
      return 'User no longer has agent access.' unless api_owner_agent?(user)
      return 'Insufficient permissions.' if ability == 'admin' && !api_owner_admin?(user)

      nil
    end

    def api_owner_agent?(user)
      (user.respond_to?(:escalated_agent?) && user.escalated_agent? == true) || api_owner_admin?(user)
    end

    def api_owner_admin?(user)
      user.respond_to?(:escalated_admin?) && user.escalated_admin? == true
    end

    def render_api_auth_error(message, status)
      render json: { message: message }, status: status
    end

    def extract_bearer_token
      header = request.headers['Authorization'].to_s
      return nil unless header.start_with?('Bearer ')

      header[7..]
    end
  end
end
