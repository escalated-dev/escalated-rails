# frozen_string_literal: true

module Escalated
  module Api
    module V1
      # General JSON API authentication for the Flutter app and integrations.
      # Credential handling is delegated to host-app callbacks configured on
      # Escalated.configuration (api_authenticator / api_registrar /
      # api_token_refresher / api_profile_updater / api_logout). Escalated owns
      # no passwords or sessions. An unconfigured callback responds 501; a
      # callback returning a falsy value is an auth failure (401).
      #
      # login/register/refresh/logout carry no token yet, so they skip token
      # authentication; validate/me/profile use the authenticated user.
      class AuthController < BaseController
        skip_before_action :authenticate_api_token!, only: %i[login register refresh logout]
        skip_before_action :enforce_rate_limit!, only: %i[login register refresh logout]

        def validate
          user = current_user

          render json: {
            user: {
              id: user.id,
              name: user.respond_to?(:name) ? user.name : user.email,
              email: user.email
            },
            abilities: @current_api_token.abilities || [],
            is_agent: user.respond_to?(:escalated_agent?) ? user.escalated_agent? : false,
            is_admin: user.respond_to?(:escalated_admin?) ? user.escalated_admin? : false,
            token_name: @current_api_token.name,
            expires_at: @current_api_token.expires_at&.iso8601
          }
        end

        def login
          delegate(Escalated.configuration.api_authenticator, request_params)
        end

        def register
          delegate(Escalated.configuration.api_registrar, request_params)
        end

        def refresh
          delegate(Escalated.configuration.api_token_refresher, bearer_token)
        end

        def logout
          callback = Escalated.configuration.api_logout
          callback.call(bearer_token) if callback.respond_to?(:call)
          render json: { data: { success: true } }
        end

        def me
          user = current_user
          render json: {
            data: {
              id: user.id,
              name: user.respond_to?(:name) ? user.name : user.email,
              email: user.email
            }
          }
        end

        def profile
          callback = Escalated.configuration.api_profile_updater
          return render_not_configured unless callback.respond_to?(:call)

          result = callback.call(current_user, request_params)
          return render_unauthorized unless result

          render json: { data: result }
        end

        private

        def delegate(callback, arg)
          return render_not_configured unless callback.respond_to?(:call)

          result = callback.call(arg)
          return render_unauthorized unless result

          render json: { data: result }
        end

        def request_params
          params.except(:controller, :action, :format).to_unsafe_h
        end

        def bearer_token
          header = request.headers['Authorization'].to_s
          header.start_with?('Bearer ') ? header[7..].to_s.strip : ''
        end

        def render_not_configured
          render json: { error: 'Authentication is not configured' }, status: :not_implemented
        end

        def render_unauthorized
          render json: { error: 'Unauthorized' }, status: :unauthorized
        end
      end
    end
  end
end
