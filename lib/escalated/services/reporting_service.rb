module Escalated
  module Services
    class ReportingService
      def ticket_volume_by_date(start_date, end_date)
        Escalated::Ticket.where(created_at: start_date..end_date)
          .group("DATE(created_at)")
          .order("DATE(created_at)")
          .count
          .map { |date, count| { date: date.to_s, count: count } }
      end

      def tickets_by_status
        Escalated::Ticket.group(:status).count.map { |status, count| { status: status, count: count } }
      end

      def tickets_by_priority
        Escalated::Ticket.group(:priority).count.map { |priority, count| { priority: priority, count: count } }
      end

      def average_response_time(start_date, end_date)
        tickets = Escalated::Ticket.where(created_at: start_date..end_date)
        total = 0.0
        count = 0

        tickets.find_each do |ticket|
          first_reply = ticket.replies.where(is_internal: false).order(:created_at).first

          if first_reply
            total += (first_reply.created_at - ticket.created_at) / 3600.0
            count += 1
          end
        end

        count > 0 ? (total / count).round(2) : 0.0
      end

      def average_resolution_time(start_date, end_date)
        tickets = Escalated::Ticket.where(created_at: start_date..end_date, status: [:resolved, :closed])
        total = 0.0
        count = 0

        tickets.find_each do |ticket|
          total += (ticket.updated_at - ticket.created_at) / 3600.0
          count += 1
        end

        count > 0 ? (total / count).round(2) : 0.0
      end

      def agent_performance(start_date, end_date)
        user_class = Escalated.configuration.user_class.constantize
        agents = user_class.joins(:escalated_assigned_tickets)
          .where(Escalated.table_name("tickets") => { created_at: start_date..end_date })
          .distinct

        agents.map do |agent|
          tickets = Escalated::Ticket.where(assigned_to: agent.id, created_at: start_date..end_date)

          {
            agent_id: agent.id,
            agent_name: agent.try(:name) || agent.try(:email),
            total_tickets: tickets.count,
            resolved_tickets: tickets.where(status: [:resolved, :closed]).count
          }
        end
      end
    end
  end
end
