module Escalated
  module Agent
    class BulkActionsController < Escalated::ApplicationController
      before_action :require_agent!

      def create
        ticket_ids = params[:ticket_ids]
        action = params[:action]
        value = params[:value]
        success_count = 0

        tickets = Escalated::Ticket.where(id: ticket_ids)

        tickets.each do |ticket|
          begin
            case action.to_s
            when "status"
              Services::TicketService.transition_status(ticket, value, actor: escalated_current_user)
            when "priority"
              Services::TicketService.change_priority(ticket, value, actor: escalated_current_user)
            when "assign"
              agent = Escalated.configuration.user_model.find(value)
              Services::AssignmentService.assign(ticket, agent, actor: escalated_current_user)
            when "tag"
              Services::TicketService.add_tags(ticket, Array(value), actor: escalated_current_user)
            when "close"
              Services::TicketService.close(ticket, actor: escalated_current_user)
            when "delete"
              ticket.destroy!
            end
            success_count += 1
          rescue StandardError => e
            Rails.logger.warn("[Escalated::BulkActions] Failed to #{action} ticket ##{ticket.id}: #{e.message}")
          end
        end

        redirect_back fallback_location: escalated.agent_tickets_path,
                      notice: I18n.t('escalated.bulk.updated', count: success_count)
      end
    end
  end
end
