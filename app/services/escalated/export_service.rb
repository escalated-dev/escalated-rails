# frozen_string_literal: true

require 'csv'
require 'json'

module Escalated
  class ExportService
    EXPORTABLE_REPORTS = %w[
      sla_breach_trends frt_distribution frt_trends frt_by_agent
      resolution_time_distribution resolution_time_trends
      agent_performance_ranking period_comparison
    ].freeze

    def initialize(from:, to:)
      @reporting = ReportingService.new(from: from, to: to)
    end

    def export_csv(report_type)
      validate_report_type!(report_type)
      data = @reporting.public_send(report_type)
      rows = flatten_for_csv(data, report_type)
      generate_csv(rows)
    end

    def export_json(report_type)
      validate_report_type!(report_type)
      data = @reporting.public_send(report_type)
      JSON.pretty_generate(data)
    end

    def export_cohort_csv(dimension)
      data = @reporting.cohort_analysis(dimension: dimension)
      rows = flatten_for_csv(data, 'cohort')
      generate_csv(rows)
    end

    def export_cohort_json(dimension)
      data = @reporting.cohort_analysis(dimension: dimension)
      JSON.pretty_generate(data)
    end

    private

    def validate_report_type!(report_type)
      return if EXPORTABLE_REPORTS.include?(report_type.to_s)

      raise ArgumentError, "Unknown report type: #{report_type}"
    end

    def flatten_for_csv(data, report_type)
      case report_type.to_s
      when 'sla_breach_trends', 'frt_trends', 'resolution_time_trends'
        data.is_a?(Array) ? data.map { |row| flatten_hash(row) } : [flatten_hash(data)]
      when 'frt_by_agent', 'agent_performance_ranking'
        data.is_a?(Array) ? data.map { |row| flatten_hash(row) } : [flatten_hash(data)]
      when 'frt_distribution', 'resolution_time_distribution'
        return [flatten_hash(data[:stats]).merge(flatten_hash(data[:percentiles] || {}))] if data.is_a?(Hash)

        [flatten_hash(data)]
      when 'period_comparison'
        if data.is_a?(Hash)
          [
            flatten_hash(data[:current] || {}).transform_keys { |k| "current_#{k}" }
                                              .merge(flatten_hash(data[:previous] || {}).transform_keys do |k|
                                                       "previous_#{k}"
                                                     end)
                                              .merge(flatten_hash(data[:changes] || {}).transform_keys do |k|
                                                       "change_#{k}"
                                                     end)
          ]
        else
          [flatten_hash(data)]
        end
      when 'cohort'
        data.is_a?(Array) ? data.map { |row| flatten_hash(row) } : [flatten_hash(data)]
      else
        data.is_a?(Array) ? data.map { |row| flatten_hash(row) } : [flatten_hash(data)]
      end
    end

    def flatten_hash(hash, prefix = nil)
      return {} unless hash.is_a?(Hash)

      hash.each_with_object({}) do |(key, value), result|
        full_key = prefix ? "#{prefix}_#{key}" : key.to_s
        if value.is_a?(Hash)
          result.merge!(flatten_hash(value, full_key))
        else
          result[full_key] = value
        end
      end
    end

    def generate_csv(rows)
      return '' if rows.empty?

      headers = rows.flat_map(&:keys).uniq
      CSV.generate do |csv|
        csv << headers
        rows.each do |row|
          csv << headers.map { |h| row[h] }
        end
      end
    end
  end
end
