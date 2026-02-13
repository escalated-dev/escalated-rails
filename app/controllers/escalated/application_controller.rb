module Escalated
  class ApplicationController < ActionController::Base
    include Pundit::Authorization

    protect_from_forgery with: :exception

    before_action :apply_middleware
    before_action :set_inertia_shared_data

    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity

    private

    def apply_middleware
      Escalated.configuration.middleware.each do |middleware_method|
        send(middleware_method) if respond_to?(middleware_method, true)
      end
    end

    def set_inertia_shared_data
      shared = {
        current_user: current_user_data,
        escalated: {
          route_prefix: Escalated.configuration.route_prefix,
          allow_customer_close: Escalated.configuration.allow_customer_close,
          max_attachments: Escalated.configuration.max_attachments,
          max_attachment_size_kb: Escalated.configuration.max_attachment_size_kb,
          guest_tickets_enabled: Escalated::EscalatedSetting.guest_tickets_enabled?,
          plugins_enabled: Escalated.configuration.plugins_enabled?,
        },
        flash: {
          success: flash[:success],
          error: flash[:error],
          notice: flash[:notice],
          alert: flash[:alert]
        }
      }

      # Share plugin UI data when plugin system is enabled
      if Escalated.configuration.plugins_enabled?
        shared[:plugin_ui] = Escalated.plugin_ui.to_shared_data
      end

      inertia_share(shared)
    end

    def current_user_data
      return nil unless respond_to?(:current_user) && current_user

      {
        id: current_user.id,
        name: current_user.respond_to?(:name) ? current_user.name : current_user.email,
        email: current_user.email,
        is_agent: current_user.respond_to?(:escalated_agent?) ? current_user.escalated_agent? : false,
        is_admin: current_user.respond_to?(:escalated_admin?) ? current_user.escalated_admin? : false
      }
    end

    def escalated_current_user
      return nil unless respond_to?(:current_user)

      current_user
    end

    def require_agent!
      unless current_user_data&.dig(:is_agent) || current_user_data&.dig(:is_admin)
        redirect_to main_app.root_path, alert: I18n.t('escalated.middleware.not_agent')
      end
    end

    def require_admin!
      unless current_user_data&.dig(:is_admin)
        redirect_to main_app.root_path, alert: I18n.t('escalated.middleware.not_admin')
      end
    end

    def user_not_authorized
      render inertia: "Escalated/Error", props: {
        status: 403,
        message: I18n.t('escalated.middleware.not_authorized')
      }, status: :forbidden
    end

    def not_found
      render inertia: "Escalated/Error", props: {
        status: 404,
        message: I18n.t('escalated.middleware.not_found')
      }, status: :not_found
    end

    def unprocessable_entity(exception)
      redirect_back(
        fallback_location: main_app.root_path,
        alert: exception.record.errors.full_messages.join(", ")
      )
    end

    def paginate(scope, per_page: 25)
      page = (params[:page] || 1).to_i
      per = (params[:per_page] || per_page).to_i

      total = scope.count
      records = scope.offset((page - 1) * per).limit(per)

      {
        data: records,
        meta: {
          current_page: page,
          per_page: per,
          total: total,
          total_pages: (total.to_f / per).ceil
        }
      }
    end
  end
end
