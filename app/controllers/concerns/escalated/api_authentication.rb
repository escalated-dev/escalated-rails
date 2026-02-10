module Escalated
  module ApiAuthentication
    extend ActiveSupport::Concern

    included do
      attr_reader :current_api_user, :current_api_token
    end

    private

    def authenticate_api_token!
      plain_text = extract_bearer_token
      unless plain_text
        render json: { message: "Unauthenticated." }, status: :unauthorized
        return
      end

      api_token = Escalated::ApiToken.find_by_plain_text(plain_text)
      unless api_token
        render json: { message: "Invalid token." }, status: :unauthorized
        return
      end

      if api_token.expired?
        render json: { message: "Token has expired." }, status: :unauthorized
        return
      end

      user = api_token.tokenable
      unless user
        render json: { message: "Token owner not found." }, status: :unauthorized
        return
      end

      # Record usage
      api_token.update_columns(
        last_used_at: Time.current,
        last_used_ip: request.remote_ip
      )

      @current_api_user = user
      @current_api_token = api_token
    end

    def extract_bearer_token
      header = request.headers["Authorization"].to_s
      return nil unless header.start_with?("Bearer ")

      header[7..]
    end
  end
end
