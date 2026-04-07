# frozen_string_literal: true

module Escalated
  module Admin
    class StatusesController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_status, only: %i[update destroy]

      def index
        statuses = Escalated::TicketStatus.ordered

        render_page 'Escalated/Admin/Statuses/Index', {
          statuses: statuses.map { |s| status_json(s) },
          categories: Escalated::TicketStatus.categories.keys
        }
      end

      def create
        status = Escalated::TicketStatus.new(status_params)

        if status.is_default
          Escalated::TicketStatus.where(category: status.category, is_default: true).update_all(is_default: false)
        end

        if status.save
          redirect_to escalated.admin_statuses_path, notice: I18n.t('escalated.admin.status.created')
        else
          redirect_back_or_to(escalated.admin_statuses_path, alert: status.errors.full_messages.join(', '))
        end
      end

      def update
        if ['1', true].include?(status_params[:is_default])
          Escalated::TicketStatus.where(category: @status.category, is_default: true)
                                 .where.not(id: @status.id)
                                 .update_all(is_default: false)
        end

        if @status.update(status_params)
          redirect_to escalated.admin_statuses_path, notice: I18n.t('escalated.admin.status.updated')
        else
          redirect_back_or_to(escalated.admin_statuses_path, alert: @status.errors.full_messages.join(', '))
        end
      end

      def destroy
        @status.destroy!
        redirect_to escalated.admin_statuses_path, notice: I18n.t('escalated.admin.status.deleted')
      end

      private

      def set_status
        @status = Escalated::TicketStatus.find(params[:id])
      end

      def status_params
        params.expect(ticket_status: %i[label category color position is_default])
      end

      def status_json(status)
        {
          id: status.id,
          label: status.label,
          category: status.category,
          color: status.color,
          position: status.position,
          is_default: status.is_default,
          created_at: status.created_at&.iso8601,
          updated_at: status.updated_at&.iso8601
        }
      end
    end
  end
end
