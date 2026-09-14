# frozen_string_literal: true

module Escalated
  module Admin
    # The advanced report screens.
    #
    # Each action renders a component from @escalated-dev/escalated, and Inertia
    # passes props by name: a name the component does not declare is not passed
    # at all. Every action here used to send `{ data:, filters: }`, which no
    # report component reads, so each screen rendered its defaults -- zeroes and
    # empty charts, on a 200. That is indistinguishable from a quiet period,
    # which is why it went unnoticed.
    #
    # The frontend also has one first-response screen and one resolution screen,
    # where this had three and two. The old paths redirect rather than 404,
    # since they have been in the routes long enough to be linked.
    class AdvancedReportsController < Escalated::ApplicationController
      # What the two time screens measure "on target" against; they show the
      # share met inside it, so it has to be stated somewhere.
      FIRST_RESPONSE_TARGET_HOURS = 4
      RESOLUTION_TARGET_HOURS = 24

      before_action :require_admin!
      before_action :set_period

      def sla_trends
        counts = reporting_service.sla_breach_counts
        trend = reporting_service.sla_breach_trends

        render_page 'Escalated/Admin/Reports/SlaTrends', {
          period_days: period_days,
          breach_trend: chart_series(trend, :date, :total_breaches),
          breach_by_type_trend: trend.map do |row|
            { label: row[:date], values: [row[:frt_breaches], row[:resolution_breaches]] }
          end,
          breach_by_department: reporting_service.sla_breach_by_department,
          breach_by_priority: reporting_service.sla_breach_by_priority,
          at_risk_tickets: reporting_service.sla_at_risk_tickets,
          total_breaches: counts[:total],
          breach_rate: counts[:rate],
          first_response_breaches: counts[:first_response],
          resolution_breaches: counts[:resolution]
        }
      end

      def response_times
        summary = reporting_service.frt_summary(target_hours: FIRST_RESPONSE_TARGET_HOURS)

        render_page 'Escalated/Admin/Reports/ResponseTimes', {
          period_days: period_days,
          avg_frt: summary[:avg],
          median_frt: summary[:median],
          p90_frt: summary[:p90],
          pct_under_target: summary[:pct_under_target],
          target_hours: FIRST_RESPONSE_TARGET_HOURS,
          distribution: distribution_series(reporting_service.frt_distribution),
          trend: chart_series(reporting_service.frt_trends, :date, :avg_hours),
          by_agent: agent_time_rows(reporting_service.frt_by_agent),
          by_department: reporting_service.frt_by_department,
          by_priority: reporting_service.frt_by_priority
        }
      end

      def resolution_times
        summary = reporting_service.resolution_summary(target_hours: RESOLUTION_TARGET_HOURS)

        render_page 'Escalated/Admin/Reports/ResolutionTimes', {
          period_days: period_days,
          avg_resolution: summary[:avg],
          median_resolution: summary[:median],
          p90_resolution: summary[:p90],
          pct_under_target: summary[:pct_under_target],
          target_hours: RESOLUTION_TARGET_HOURS,
          distribution: distribution_series(reporting_service.resolution_time_distribution),
          trend: chart_series(reporting_service.resolution_time_trends, :date, :avg_hours),
          by_agent: agent_time_rows(reporting_service.resolution_by_agent),
          by_department: reporting_service.resolution_by_department,
          by_channel: reporting_service.resolution_by_channel
        }
      end

      def agent_ranking
        render_page 'Escalated/Admin/Reports/AgentRanking', {
          period_days: period_days,
          agents: reporting_service.agent_performance_ranking.map do |agent|
            {
              agent_id: agent[:agent_id],
              agent_name: agent[:agent_name],
              volume: agent[:total_tickets],
              resolution_rate: agent[:resolution_rate],
              avg_frt: agent[:avg_frt_hours],
              avg_resolution: agent[:avg_resolution_hours],
              csat: agent[:avg_csat],
              composite_score: agent[:composite_score]
            }
          end
        }
      end

      def cohorts
        # The screen shows every dimension at once, in tabs. This used to serve
        # one at a time, chosen by a query parameter the screen does not send.
        render_page 'Escalated/Admin/Reports/Cohorts', {
          period_days: period_days,
          by_tag: cohort_rows('tag'),
          by_department: cohort_rows('department'),
          by_channel: cohort_rows('channel'),
          by_type: cohort_rows('type'),
          by_priority: cohort_rows('priority')
        }
      end

      def comparison
        data = reporting_service.period_comparison

        duration = @period_end - @period_start

        render_page 'Escalated/Admin/Reports/Comparison', {
          period_days: period_days,
          current: comparison_side(
            data[:current],
            reporting_service.volume_by_date(from: @period_start, to: @period_end)
          ),
          previous: comparison_side(
            data[:previous],
            reporting_service.volume_by_date(from: @period_start - duration, to: @period_start)
          )
        }
      end

      # The first-response screen was three paths and the resolution screen two.
      # Both are one screen in the frontend; these keep the old links working.
      def frt_distribution = redirect_to_response_times
      def frt_trends = redirect_to_response_times
      def frt_by_agent = redirect_to_response_times
      def resolution_distribution = redirect_to_resolution_times
      def resolution_trends = redirect_to_resolution_times

      # Kept under its old name as well, which the navigation may still use.
      def cohort = redirect_to(escalated.admin_reports_cohorts_path(request.query_parameters))

      def export
        report_type = params[:report_type]
        format = params[:export_format] || 'csv'
        export_service = Escalated::ExportService.new(from: @period_start, to: @period_end)

        content = if params[:dimension].present?
                    if format == 'json'
                      export_service.export_cohort_json(params[:dimension])
                    else
                      export_service.export_cohort_csv(params[:dimension])
                    end
                  else
                    format == 'json' ? export_service.export_json(report_type) : export_service.export_csv(report_type)
                  end

        content_type = format == 'json' ? 'application/json' : 'text/csv'
        filename = "#{report_type || 'cohort'}_#{Time.current.strftime('%Y%m%d')}.#{format}"

        send_data content, filename: filename, type: content_type, disposition: 'attachment'
      end

      private

      def redirect_to_response_times
        redirect_to escalated.admin_reports_response_times_path(request.query_parameters)
      end

      def redirect_to_resolution_times
        redirect_to escalated.admin_reports_resolution_times_path(request.query_parameters)
      end

      def set_period
        @period_start = parse_date(params[:from]) || 30.days.ago.beginning_of_day
        @period_end = parse_date(params[:to]) || Time.current.end_of_day
      end

      # The screens take a day count and send one back when the period changes;
      # this controller works in timestamps.
      def period_days
        (@period_end.to_date - @period_start.to_date).to_i.clamp(1, 3650)
      end

      def parse_date(value)
        return nil if value.blank?

        Time.zone.parse(value)
      rescue ArgumentError
        nil
      end

      def reporting_service
        @reporting_service ||= Escalated::ReportingService.new(from: @period_start, to: @period_end)
      end

      # Every chart on these screens reads { label:, value: }.
      def chart_series(rows, label_key, value_key)
        rows.map { |row| { label: row[label_key], value: row[value_key] || 0 } }
      end

      def distribution_series(distribution)
        (distribution[:buckets] || []).map { |bucket| { label: bucket[:range], value: bucket[:count] } }
      end

      # The agent table on the time screens sorts on these four keys.
      def agent_time_rows(rows)
        rows.map do |row|
          percentiles = row[:percentiles] || {}

          {
            agent_id: row[:agent_id],
            agent_name: row[:agent_name],
            count: row[:count],
            avg: row[:avg_hours],
            median: percentiles[:p50] || 0,
            p90: percentiles[:p90] || 0
          }
        end
      end

      def cohort_rows(dimension)
        rows = reporting_service.cohort_analysis(dimension: dimension)
        return [] unless rows.is_a?(Array)

        rows.map do |row|
          {
            name: row[:name],
            volume: row[:total],
            avg_resolution: row[:avg_resolution_hours] || 0,
            breach_rate: row[:breach_rate] || 0,
            csat: row[:csat] || 0
          }
        end
      end

      def comparison_side(stats, volume_trend)
        {
          total_tickets: stats[:total_created],
          resolved_tickets: stats[:total_resolved],
          avg_frt: stats[:avg_frt_hours] || 0,
          avg_resolution: stats[:avg_resolution_hours] || 0,
          sla_compliance: stats[:resolution_rate],
          csat: stats[:csat] || 0,
          breach_count: stats[:sla_breaches],
          volume_trend: volume_trend
        }
      end
    end
  end
end
