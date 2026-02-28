module Escalated
  module Admin
    class AuditLogsController < Escalated::ApplicationController
      before_action :require_admin!

      def index
        scope = Escalated::AuditLog.includes(:user).recent

        scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
        scope = scope.where(action: params[:action]) if params[:action].present?
        scope = scope.where(auditable_type: params[:auditable_type]) if params[:auditable_type].present?
        scope = scope.where("created_at >= ?", params[:date_from]) if params[:date_from].present?
        scope = scope.where("created_at <= ?", params[:date_to].to_time.end_of_day) if params[:date_to].present?

        result = paginate(scope)

        render inertia: "Escalated/Admin/AuditLogs/Index", props: {
          logs: result[:data].map { |l| log_json(l) },
          meta: result[:meta],
          filters: {
            user_id: params[:user_id],
            action: params[:action],
            auditable_type: params[:auditable_type],
            date_from: params[:date_from],
            date_to: params[:date_to]
          }
        }
      end

      private

      def log_json(log)
        {
          id: log.id,
          action: log.action,
          auditable_type: log.auditable_type,
          auditable_id: log.auditable_id,
          changes: log.changes,
          ip_address: log.ip_address,
          user_agent: log.user_agent,
          user: log.user ? {
            id: log.user.id,
            name: log.user.respond_to?(:name) ? log.user.name : log.user.email,
            email: log.user.email
          } : nil,
          created_at: log.created_at&.iso8601
        }
      end
    end
  end
end
