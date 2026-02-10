module Escalated
  module Agent
    class DashboardController < Escalated::ApplicationController
      before_action :require_agent!

      def index
        my_tickets = Escalated::Ticket.assigned_to(escalated_current_user.id)
        all_open = Escalated::Ticket.by_open

        stats = {
          my_open: my_tickets.by_open.count,
          my_waiting: my_tickets.where(status: :waiting_on_customer).count,
          unassigned: all_open.unassigned.count,
          total_open: all_open.count,
          breached_sla: all_open.breached_sla.count,
          resolved_today: Escalated::Ticket.where(
            status: :resolved,
            resolved_at: Time.current.beginning_of_day..Time.current.end_of_day
          ).count,
          avg_first_response: calculate_avg_first_response,
          avg_resolution_time: calculate_avg_resolution_time,
          avg_csat_rating: calculate_avg_csat_rating,
          total_ratings: Escalated::SatisfactionRating.count,
          resolved_with_rating_count: Escalated::SatisfactionRating
            .joins(:ticket)
            .where("#{Escalated.table_name('tickets')}.status" => [:resolved, :closed])
            .count
        }

        recent_tickets = my_tickets.by_open.recent.limit(10)
        unassigned_tickets = all_open.unassigned.recent.limit(10)
        breached_tickets = all_open.breached_sla.recent.limit(10)

        render inertia: "Escalated/Agent/Dashboard", props: {
          stats: stats,
          recent_tickets: recent_tickets.map { |t| ticket_summary_json(t) },
          unassigned_tickets: unassigned_tickets.map { |t| ticket_summary_json(t) },
          breached_tickets: breached_tickets.map { |t| ticket_summary_json(t) },
          sla_stats: Services::SlaService.stats
        }
      end

      private

      def calculate_avg_first_response
        tickets = Escalated::Ticket
          .where.not(first_response_at: nil)
          .where(created_at: 30.days.ago..Time.current)

        return 0 if tickets.empty?

        total_seconds = tickets.sum { |t| (t.first_response_at - t.created_at).to_f }
        avg_seconds = total_seconds / tickets.count
        (avg_seconds / 3600.0).round(1) # Return in hours
      end

      def calculate_avg_resolution_time
        tickets = Escalated::Ticket
          .where.not(resolved_at: nil)
          .where(created_at: 30.days.ago..Time.current)

        return 0 if tickets.empty?

        total_seconds = tickets.sum { |t| (t.resolved_at - t.created_at).to_f }
        avg_seconds = total_seconds / tickets.count
        (avg_seconds / 3600.0).round(1) # Return in hours
      end

      def calculate_avg_csat_rating
        ratings = Escalated::SatisfactionRating.all
        return 0.0 if ratings.empty?

        (ratings.average(:rating).to_f).round(2)
      end

      def ticket_summary_json(ticket)
        {
          id: ticket.id,
          reference: ticket.reference,
          subject: ticket.subject,
          status: ticket.status,
          priority: ticket.priority,
          requester_name: ticket.requester.respond_to?(:name) ? ticket.requester.name : ticket.requester&.email,
          department: ticket.department&.name,
          created_at: ticket.created_at&.iso8601,
          updated_at: ticket.updated_at&.iso8601,
          sla_breached: ticket.sla_breached,
          sla_first_response_due_at: ticket.sla_first_response_due_at&.iso8601,
          sla_resolution_due_at: ticket.sla_resolution_due_at&.iso8601
        }
      end
    end
  end
end
