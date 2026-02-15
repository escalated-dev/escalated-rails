module Escalated
  module Api
    module V1
      class AuthController < BaseController
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
      end
    end
  end
end
