# frozen_string_literal: true

module Escalated
  module Agent
    # The agent's in-app notifications (ADR 2026-11-05-agent-panel-data,
    # section 4). JSON only; 404 while the feed is off.
    class NotificationsController < Escalated::ApplicationController
      before_action :require_agent!
      before_action :require_feed!

      def index
        feed = Services::AgentNotificationFeed
        page = whole(params[:page])
        per_page = whole(params[:per_page])
        return invalid('page', 'The page field must be at least 1.') if page == :invalid || (page && page < 1)
        if per_page == :invalid || (per_page && !per_page.between?(1, feed::MAX_PER_PAGE))
          return invalid('per_page', "The per page field must be between 1 and #{feed::MAX_PER_PAGE}.")
        end

        page ||= 1
        per_page ||= feed::PER_PAGE
        scope = Escalated::AgentNotification.for_user(escalated_current_user.id)
        scope = scope.unread if ActiveModel::Type::Boolean.new.cast(params[:unread])
        total = scope.count
        rows = scope.order(created_at: :desc, id: :desc).offset((page - 1) * per_page).limit(per_page).to_a

        render json: {
          data: feed.present(rows, escalated_current_user),
          meta: { current_page: page, last_page: [(total.to_f / per_page).ceil, 1].max, per_page: per_page,
                  total: total },
          unread_count: feed.unread_count(escalated_current_user)
        }
      end

      def read
        row = Escalated::AgentNotification.for_user(escalated_current_user.id).find_by(id: params[:id])
        return head(:not_found) unless row

        row.update!(read_at: Time.current) if row.read_at.nil?
        render json: { unread_count: Services::AgentNotificationFeed.unread_count(escalated_current_user) }
      end

      def read_all
        Escalated::AgentNotification.for_user(escalated_current_user.id).unread.update_all(read_at: Time.current)
        render json: { unread_count: 0 }
      end

      private

      def require_feed!
        head(:not_found) unless Services::AgentNotificationFeed.available?
      end

      def whole(value)
        return nil if value.blank?

        value.to_s.match?(/\A\d+\z/) ? value.to_i : :invalid
      end

      def invalid(field, message)
        render json: { message: message, errors: { field => [message] } }, status: :unprocessable_content
      end
    end
  end
end
