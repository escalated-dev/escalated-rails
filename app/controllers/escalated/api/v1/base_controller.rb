module Escalated
  module Api
    module V1
      class BaseController < ActionController::API
        include Escalated::ApiAuthentication
        include Escalated::ApiRateLimiting

        before_action :check_api_enabled!
        before_action :authenticate_api_token!
        before_action :enforce_rate_limit!

        rescue_from ActiveRecord::RecordNotFound, with: :not_found
        rescue_from ActiveRecord::RecordInvalid, with: :unprocessable

        private

        def check_api_enabled!
          unless Escalated.configuration.api_enabled
            render json: { message: "API is not enabled." }, status: :not_found
          end
        end

        def current_user
          @current_api_user
        end

        def not_found
          render json: { message: "The requested resource was not found." }, status: :not_found
        end

        def unprocessable(exception)
          render json: {
            message: "Validation failed.",
            errors: exception.record.errors.full_messages
          }, status: :unprocessable_entity
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
  end
end
