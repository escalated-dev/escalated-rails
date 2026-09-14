# frozen_string_literal: true

module Escalated
  class ReportingService
    # The figures the report screens read, in the shape they read them.
    #
    # ReportingService answers the API, where a report is a nested object --
    # a distribution with its buckets, stats and percentiles inside it. The
    # screens read something flatter and differently named: a list of
    # { label:, value: } per chart, four headline numbers per screen.
    #
    # Keeping that here rather than in the controller means the mapping is
    # tested where the data is, and keeps ReportingService itself down to the
    # size the linter allows.
    module ScreenMetrics
      # Headline figures for the first-response screen.
      #
      # The distribution and the trend are the body of that screen; these are the
      # four tiles above them, and without them it renders zeroes over a chart
      # that is plainly not describing zero.
      def frt_summary(target_hours: 4)
        summarise(frt_values, target_hours)
      end

      # The same four for the resolution screen.
      def resolution_summary(target_hours: 24)
        summarise(resolution_values, target_hours)
      end

      # Average first response per department and per priority, as the charts
      # read them: a label and a value.
      def frt_by_department
        average_hours_by(:department_id, :first_response_at) do |id|
          Escalated::Department.find_by(id: id)&.name || 'Unassigned'
        end
      end

      def frt_by_priority
        average_hours_by(:priority, :first_response_at, &:to_s)
      end

      def resolution_by_department
        average_hours_by(:department_id, :resolved_at) do |id|
          Escalated::Department.find_by(id: id)&.name || 'Unassigned'
        end
      end

      def resolution_by_channel
        average_hours_by(:channel, :resolved_at) { |channel| channel.presence || 'unknown' }
      end

      # Counts for the SLA screen, over the same window as its trends.
      def sla_breach_counts
        total = @tickets.count
        breached = @tickets.where(sla_breached: true).count

        {
          total: breached,
          rate: total.positive? ? (breached.to_f / total * 100).round(1) : 0.0,
          first_response: @tickets.where(sla_breached: true).where(first_response_at: nil).count,
          resolution: @tickets.where(sla_breached: true).where(resolved_at: nil).count
        }
      end

      def sla_breach_by_department
        counts_by(:department_id, @tickets.where(sla_breached: true)) do |id|
          Escalated::Department.find_by(id: id)&.name || 'Unassigned'
        end
      end

      def sla_breach_by_priority
        counts_by(:priority, @tickets.where(sla_breached: true), &:to_s)
      end

      # Open tickets whose SLA has not been missed yet but is close, soonest
      # first. The screen sorts them into bands by hours_remaining.
      def sla_at_risk_tickets(within_hours: 8, limit: 50)
        deadline = Time.current + within_hours.hours

        Escalated::Ticket.where(resolved_at: nil, sla_breached: [false, nil])
                         .where(sla_resolution_due_at: Time.current..deadline)
                         .order(:sla_resolution_due_at)
                         .limit(limit)
                         .map do |ticket|
          {
            id: ticket.id,
            reference: ticket.reference,
            subject: ticket.subject,
            priority: ticket.priority,
            hours_remaining: ((ticket.sla_resolution_due_at - Time.current) / 3600.0).round(1)
          }
        end
      end

      private

      def resolution_values
        @tickets.where.not(resolved_at: nil)
                .pluck(:resolved_at, :created_at)
                .map { |r, c| ((r - c) / 3600.0).round(2) }
      end

      def summarise(values, target_hours)
        return { avg: 0, median: 0, p90: 0, pct_under_target: 0 } if values.empty?

        sorted = values.sort
        within = sorted.count { |v| v <= target_hours }

        {
          avg: safe_avg(sorted) || 0,
          median: pct(sorted, 50),
          p90: pct(sorted, 90),
          pct_under_target: (within.to_f / sorted.size * 100).round(1)
        }
      end

      # [{ label:, value: }] -- the shape every chart on these screens reads.
      def average_hours_by(column, stamp)
        grouped = @tickets.where.not(stamp => nil)
                          .pluck(column, stamp, :created_at)
                          .group_by(&:first)

        rows = grouped.map do |key, entries|
          hours = entries.map { |_, stamped, created| (stamped - created) / 3600.0 }
          { label: yield(key), value: (hours.sum / hours.size).round(2) }
        end

        rows.sort_by { |row| -row[:value] }
      end

      def counts_by(column, scope)
        scope.group(column).count.map { |key, count| { label: yield(key), value: count } }
             .sort_by { |row| -row[:value] }
      end
    end
  end
end
