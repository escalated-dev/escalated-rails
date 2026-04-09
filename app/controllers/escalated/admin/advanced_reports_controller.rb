# frozen_string_literal: true

module Escalated
  module Admin
    class AdvancedReportsController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_period

      def sla_trends
        data = reporting_service.sla_breach_trends
        render_report('Escalated/Admin/Reports/SlaTrends', data)
      end

      def frt_distribution
        data = reporting_service.frt_distribution
        render_report('Escalated/Admin/Reports/FrtDistribution', data)
      end

      def frt_trends
        data = reporting_service.frt_trends
        render_report('Escalated/Admin/Reports/FrtTrends', data)
      end

      def frt_by_agent
        data = reporting_service.frt_by_agent
        render_report('Escalated/Admin/Reports/FrtByAgent', data)
      end

      def resolution_distribution
        data = reporting_service.resolution_time_distribution
        render_report('Escalated/Admin/Reports/ResolutionDistribution', data)
      end

      def resolution_trends
        data = reporting_service.resolution_time_trends
        render_report('Escalated/Admin/Reports/ResolutionTrends', data)
      end

      def agent_ranking
        data = reporting_service.agent_performance_ranking
        render_report('Escalated/Admin/Reports/AgentRanking', data)
      end

      def cohort
        dimension = params[:dimension] || 'department'
        data = reporting_service.cohort_analysis(dimension: dimension)
        render_report('Escalated/Admin/Reports/Cohort', data, dimension: dimension)
      end

      def comparison
        data = reporting_service.period_comparison
        render_report('Escalated/Admin/Reports/Comparison', data)
      end

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

      def set_period
        @period_start = parse_date(params[:from]) || 30.days.ago.beginning_of_day
        @period_end = parse_date(params[:to]) || Time.current.end_of_day
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

      def render_report(component, data, extra = {})
        render_page component, {
          data: data,
          filters: { from: @period_start.iso8601, to: @period_end.iso8601 }
        }.merge(extra)
      end
    end
  end
end
