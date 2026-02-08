module Escalated
  module Admin
    class ReportsController < Escalated::ApplicationController
      before_action :require_admin!

      def index
        period_start = parse_date(params[:from]) || 30.days.ago.beginning_of_day
        period_end = parse_date(params[:to]) || Time.current.end_of_day

        tickets_in_period = Escalated::Ticket.where(created_at: period_start..period_end)

        stats = {
          overview: {
            total_created: tickets_in_period.count,
            total_resolved: tickets_in_period.where.not(resolved_at: nil).count,
            total_closed: tickets_in_period.where(status: :closed).count,
            currently_open: Escalated::Ticket.by_open.count,
            currently_unassigned: Escalated::Ticket.by_open.unassigned.count
          },
          by_status: Escalated::Ticket.statuses.keys.each_with_object({}) { |status, hash|
            hash[status] = Escalated::Ticket.where(status: status).count
          },
          by_priority: Escalated::Ticket.priorities.keys.each_with_object({}) { |priority, hash|
            hash[priority] = tickets_in_period.where(priority: priority).count
          },
          by_department: Escalated::Department.ordered.map { |dept|
            {
              id: dept.id,
              name: dept.name,
              total: tickets_in_period.where(department_id: dept.id).count,
              open: Escalated::Ticket.by_open.where(department_id: dept.id).count
            }
          },
          sla: Services::SlaService.stats,
          performance: {
            avg_first_response_hours: calculate_avg(:first_response, period_start, period_end),
            avg_resolution_hours: calculate_avg(:resolution, period_start, period_end),
            tickets_per_day: tickets_in_period.count.to_f / [(period_end - period_start) / 1.day, 1].max
          },
          trends: calculate_daily_trends(period_start, period_end),
          top_agents: calculate_top_agents(period_start, period_end)
        }

        render inertia: "Escalated/Admin/Reports/Index", props: {
          stats: stats,
          filters: {
            from: period_start.iso8601,
            to: period_end.iso8601
          }
        }
      end

      private

      def parse_date(value)
        return nil unless value.present?

        Time.zone.parse(value)
      rescue ArgumentError
        nil
      end

      def calculate_avg(type, from, to)
        scope = Escalated::Ticket.where(created_at: from..to)

        case type
        when :first_response
          tickets = scope.where.not(first_response_at: nil)
          return 0 if tickets.empty?

          total = tickets.sum { |t| (t.first_response_at - t.created_at).to_f }
          (total / tickets.count / 3600.0).round(1)
        when :resolution
          tickets = scope.where.not(resolved_at: nil)
          return 0 if tickets.empty?

          total = tickets.sum { |t| (t.resolved_at - t.created_at).to_f }
          (total / tickets.count / 3600.0).round(1)
        end
      end

      def calculate_daily_trends(from, to)
        days = ((to - from) / 1.day).ceil
        days = [days, 90].min # Cap at 90 days

        (0...days).map do |i|
          day_start = from + i.days
          day_end = day_start + 1.day

          {
            date: day_start.strftime("%Y-%m-%d"),
            created: Escalated::Ticket.where(created_at: day_start..day_end).count,
            resolved: Escalated::Ticket.where(resolved_at: day_start..day_end).count,
            closed: Escalated::Ticket.where(closed_at: day_start..day_end).count
          }
        end
      end

      def calculate_top_agents(from, to)
        resolved_counts = Escalated::Ticket
          .where(resolved_at: from..to)
          .where.not(assigned_to: nil)
          .group(:assigned_to)
          .count
          .sort_by { |_, count| -count }
          .first(10)

        resolved_counts.map do |agent_id, count|
          agent = Escalated.configuration.user_model.find_by(id: agent_id)
          next unless agent

          {
            id: agent.id,
            name: agent.respond_to?(:name) ? agent.name : agent.email,
            resolved_count: count,
            avg_resolution_hours: calculate_agent_avg_resolution(agent_id, from, to)
          }
        end.compact
      end

      def calculate_agent_avg_resolution(agent_id, from, to)
        tickets = Escalated::Ticket
          .where(assigned_to: agent_id, resolved_at: from..to)
          .where.not(resolved_at: nil)

        return 0 if tickets.empty?

        total = tickets.sum { |t| (t.resolved_at - t.created_at).to_f }
        (total / tickets.count / 3600.0).round(1)
      end
    end
  end
end
