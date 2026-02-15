module Escalated
  module Admin
    class ApiTokensController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_token, only: [:update, :destroy]

      def index
        tokens = Escalated::ApiToken.includes(:tokenable).order(created_at: :desc).map { |token|
          {
            id: token.id,
            name: token.name,
            user_name: token.tokenable.respond_to?(:name) ? token.tokenable.name : token.tokenable&.email,
            user_email: token.tokenable&.email,
            abilities: token.abilities,
            last_used_at: token.last_used_at&.iso8601,
            last_used_ip: token.last_used_ip,
            expires_at: token.expires_at&.iso8601,
            is_expired: token.expired?,
            created_at: token.created_at&.iso8601
          }
        }

        users = agent_list

        render inertia: "Escalated/Admin/ApiTokens/Index", props: {
          tokens: tokens,
          users: users,
          api_enabled: Escalated.configuration.api_enabled
        }
      end

      def create
        user = Escalated.configuration.user_model.find(params[:user_id])

        expires_at = if params[:expires_in_days].present?
          params[:expires_in_days].to_i.days.from_now
        else
          nil
        end

        abilities = params[:abilities].present? ? Array(params[:abilities]) : ["*"]

        result = Escalated::ApiToken.create_token(
          user,
          params[:name],
          abilities,
          expires_at
        )

        redirect_back(
          fallback_location: escalated.admin_api_tokens_path,
          flash: {
            success: "API token created.",
            plain_text_token: result[:plain_text_token]
          }
        )
      end

      def update
        update_attrs = {}
        update_attrs[:name] = params[:name] if params[:name].present?
        update_attrs[:abilities] = Array(params[:abilities]) if params[:abilities].present?

        @token.update!(update_attrs)

        redirect_back(
          fallback_location: escalated.admin_api_tokens_path,
          flash: { success: "Token updated." }
        )
      end

      def destroy
        @token.destroy!

        redirect_back(
          fallback_location: escalated.admin_api_tokens_path,
          flash: { success: "Token revoked." }
        )
      end

      private

      def set_token
        @token = Escalated::ApiToken.find(params[:id])
      end

      def agent_list
        if Escalated.configuration.user_model.respond_to?(:escalated_agents)
          Escalated.configuration.user_model.escalated_agents.map { |a|
            { id: a.id, name: a.respond_to?(:name) ? a.name : a.email, email: a.email }
          }
        else
          []
        end
      end
    end
  end
end
