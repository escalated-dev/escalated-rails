# frozen_string_literal: true

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
          by_status: Escalated::Ticket.statuses.keys.index_with do |status|
            Escalated::Ticket.where(status: status).count
          end,
          by_priority: Escalated::Ticket.priorities.keys.index_with do |priority|
            tickets_in_period.where(priority: priority).count
          end,
          by_department: Escalated::Department.ordered.map do |dept|
            {
              id: dept.id,
              name: dept.name,
              total: tickets_in_period.where(department_id: dept.id).count,
              open: Escalated::Ticket.by_open.where(department_id: dept.id).count
            }
          end,
          sla: Services::SlaService.stats,
          performance: {
            avg_first_response_hours: calculate_avg(:first_response, period_start, period_end),
            avg_resolution_hours: calculate_avg(:resolution, period_start, period_end),
            tickets_per_day: tickets_in_period.count.to_f / [(period_end - period_start) / 1.day, 1].max
          },
          trends: calculate_daily_trends(period_start, period_end),
          top_agents: calculate_top_agents(period_start, period_end),
          csat: calculate_csat_stats(period_start, period_end)
        }

        # The overview screen takes these flat, not as the nested `stats` the
        # JSON endpoints below return. Handed the nested hash it renders zeroes
        # across the board, because every prop falls back to its default -- a
        # dashboard of zeroes reads as a quiet week rather than as a wiring
        # fault, which is why this went unnoticed.
        render_page 'Escalated/Admin/Reports', {
          period_days: ((period_end - period_start) / 1.day).round,
          total_tickets: stats[:overview][:total_created],
          resolved_tickets: stats[:overview][:total_resolved],
          avg_first_response_hours: stats[:performance][:avg_first_response_hours],
          sla_breach_count: stats[:sla][:total_breached] || 0,
          by_status: stats[:by_status],
          by_priority: stats[:by_priority],
          csat: stats[:csat]
        }
      end

      # The dashboard's tabs (Overview, Agents, SLA, CSAT), as escalated-laravel
      # sends them. This used to send today/this_week counts under names the
      # component does not declare, so every tab rendered its defaults.
      def dashboard
        render_page 'Escalated/Admin/Reports/Dashboard', {
          period_days: period_days,
          volume: window.daily_volume,
          by_status: window.status_counts,
          by_priority: window.priority_counts,
          avg_response_hours: window.average_response_hours,
          avg_resolution_hours: window.average_resolution_hours,
          sla_compliance: window.sla_compliance_rate,
          csat_average: window.csat_average,
          agent_performance: window.agent_performance_rows
        }
      end

      def agents
        render_page 'Escalated/Admin/Reports/AgentMetrics', {
          period_days: period_days,
          agents: window.agent_performance_rows
        }
      end

      def sla
        render_page 'Escalated/Admin/Reports/SlaReport', {
          period_days: period_days,
          compliance_rate: window.sla_compliance_rate,
          compliance_by_policy: window.sla_compliance_by_policy,
          breaches: window.sla_breach_details
        }
      end

      def csat
        tickets = window.tickets_count
        total_ratings = window.ratings_count

        render_page 'Escalated/Admin/Reports/CsatReport', {
          period_days: period_days,
          csat_average: window.csat_average,
          response_rate: tickets.positive? ? (total_ratings.to_f / tickets * 100).round(1) : 0,
          total_ratings: total_ratings,
          by_agent: window.csat_by_agent,
          over_time: window.csat_over_time
        }
      end

      # One agent over the period, against the period of the same length before
      # it, under the names Reports/AgentDetail declares.
      def agent_detail
        agent = Escalated.configuration.user_model.find(params[:id])
        current = window.agent_figures(agent.id)
        previous = Escalated::ReportingService.new(from: period_start - period_days.days, to: period_start)
                                              .agent_figures(agent.id)

        render_page 'Escalated/Admin/Reports/AgentDetail', {
          period_days: period_days,
          agent: {
            id: agent.id,
            name: agent.respond_to?(:name) && agent.name.present? ? agent.name : agent.email,
            email: agent.email
          },
          **current,
          prev_total_tickets: previous[:total_tickets],
          prev_resolved_tickets: previous[:resolved_tickets],
          prev_avg_frt: previous[:avg_frt],
          prev_avg_resolution: previous[:avg_resolution],
          prev_csat_score: previous[:csat_score]
        }
      end

      private

      # The screens send the period as `days` (default 30, at most a year).
      def period_days
        @period_days ||= (params[:days].presence || 30).to_i.clamp(1, 365)
      end

      def period_start
        @period_start ||= period_days.days.ago
      end

      def window
        @window ||= Escalated::ReportingService.new(from: period_start, to: Time.current)
      end

      def parse_date(value)
        return nil if value.blank?

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
            date: day_start.strftime('%Y-%m-%d'),
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

      def calculate_csat_stats(from, to)
        ratings = Escalated::SatisfactionRating.where(created_at: from..to)

        total = ratings.count
        return { average: 0, total: 0, breakdown: {} } if total.zero?

        average = ratings.average(:rating).to_f.round(2)
        breakdown = (1..5).index_with do |star|
          ratings.where(rating: star).count
        end

        {
          average: average,
          total: total,
          breakdown: breakdown
        }
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
