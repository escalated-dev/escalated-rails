module Escalated
  module Api
    module V1
      class DashboardController < BaseController
        def index
          user_id = current_user.id

          render json: {
            stats: {
              open: Escalated::Ticket.by_open.count,
              my_assigned: Escalated::Ticket.assigned_to(user_id).by_open.count,
              unassigned: Escalated::Ticket.by_open.unassigned.count,
              sla_breached: Escalated::Ticket.by_open.breached_sla.count,
              resolved_today: Escalated::Ticket.where(
                status: :resolved
              ).where(
                resolved_at: Time.current.beginning_of_day..Time.current.end_of_day
              ).count
            },
            recent_tickets: Escalated::Ticket
              .includes(:requester, :assignee, :department)
              .recent
              .limit(10)
              .map { |t| ticket_summary_json(t) },
            needs_attention: {
              sla_breaching: Escalated::Ticket
                .by_open
                .breached_sla
                .includes(:requester, :assignee)
                .limit(5)
                .map { |t| attention_ticket_json(t) },
              unassigned_urgent: Escalated::Ticket
                .by_open
                .unassigned
                .where(priority: [:urgent, :critical])
                .includes(:requester)
                .limit(5)
                .map { |t| attention_ticket_json(t) }
            },
            my_performance: {
              resolved_this_week: Escalated::Ticket
                .assigned_to(user_id)
                .where("resolved_at >= ?", Time.current.beginning_of_week)
                .count
            }
          }
        end

        private

        def ticket_summary_json(ticket)
          {
            id: ticket.id,
            reference: ticket.reference,
            subject: ticket.subject,
            status: ticket.status,
            priority: ticket.priority,
            requester_name: ticket.requester_name,
            assignee_name: ticket.assignee.respond_to?(:name) ? ticket.assignee.name : ticket.assignee&.email,
            created_at: ticket.created_at&.iso8601
          }
        end

        def attention_ticket_json(ticket)
          {
            reference: ticket.reference,
            subject: ticket.subject,
            priority: ticket.priority,
            requester_name: ticket.requester_name
          }
        end
      end
    end
  end
end
