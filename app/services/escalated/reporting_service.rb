# frozen_string_literal: true

module Escalated
  class ReportingService
    def initialize(from:, to:)
      @from = from
      @to = to
      @tickets = Escalated::Ticket.where(created_at: @from..@to)
    end

    # SLA breach trends over time
    def sla_breach_trends
      date_series.map do |date|
        day_range = date.all_day
        day_tickets = Escalated::Ticket.where(created_at: ..date.end_of_day)
        {
          date: date.strftime('%Y-%m-%d'),
          frt_breaches: day_tickets.where(sla_breached: true, first_response_at: nil)
                        .where(sla_first_response_due_at: day_range).count,
          resolution_breaches: day_tickets.where(sla_breached: true, resolved_at: nil)
                               .where(sla_resolution_due_at: day_range).count,
          total_breaches: day_tickets.where(sla_breached: true).where(updated_at: day_range).count
        }
      end
    end

    # First response time distribution with buckets and percentiles
    def frt_distribution
      values = frt_values
      build_distribution(values, 'hours')
    end

    # Daily FRT trend averages
    def frt_trends
      date_series.map do |date|
        day_range = date.all_day
        frts = Escalated::Ticket.where(first_response_at: day_range)
                                .where.not(first_response_at: nil)
                                .pluck(:first_response_at, :created_at)
                                .map { |fr, cr| (fr - cr) / 3600.0 }
        {
          date: date.strftime('%Y-%m-%d'),
          avg_hours: safe_avg(frts),
          count: frts.size,
          percentiles: frts.any? ? percentiles(frts) : {}
        }
      end
    end

    # FRT broken down by agent
    def frt_by_agent
      tickets = @tickets.where.not(first_response_at: nil, assigned_to: nil)
      grouped = tickets.pluck(:assigned_to, :first_response_at, :created_at).group_by(&:first)
      grouped.filter_map do |agent_id, rows|
        frts = rows.map { |_, fr, cr| (fr - cr) / 3600.0 }
        agent = Escalated.configuration.user_model.find_by(id: agent_id)
        next unless agent

        {
          agent_id: agent_id,
          agent_name: agent.respond_to?(:name) ? agent.name : agent.email,
          avg_hours: (frts.sum / frts.size).round(2),
          count: frts.size,
          percentiles: percentiles(frts)
        }
      end.sort_by { |a| a[:avg_hours] }
    end

    # Resolution time distribution
    def resolution_time_distribution
      tickets = @tickets.where.not(resolved_at: nil)
      values = tickets.pluck(:resolved_at, :created_at).map { |r, c| ((r - c) / 3600.0).round(2) }
      build_distribution(values, 'hours')
    end

    # Daily resolution time trends
    def resolution_time_trends
      date_series.map do |date|
        day_range = date.all_day
        times = Escalated::Ticket.where(resolved_at: day_range)
                                 .where.not(resolved_at: nil)
                                 .pluck(:resolved_at, :created_at)
                                 .map { |r, c| (r - c) / 3600.0 }
        {
          date: date.strftime('%Y-%m-%d'),
          avg_hours: safe_avg(times),
          count: times.size,
          percentiles: times.any? ? percentiles(times) : {}
        }
      end
    end

    # Agent performance ranking with composite score
    def agent_performance_ranking
      agent_ids = @tickets.where.not(assigned_to: nil).distinct.pluck(:assigned_to)
      rankings = agent_ids.filter_map do |agent_id|
        agent = Escalated.configuration.user_model.find_by(id: agent_id)
        next unless agent

        build_agent_ranking(agent_id, agent)
      end
      rankings.sort_by { |r| -(r[:composite_score] || 0) }
    end

    # Cohort analysis by tag, department, channel, or type
    def cohort_analysis(dimension:)
      case dimension.to_s
      when 'tag' then cohort_by_tag
      when 'department' then cohort_by_department
      when 'channel' then cohort_by_channel
      when 'type' then cohort_by_type
      else { error: "Unknown dimension: #{dimension}" }
      end
    end

    # Compare current period vs previous period of same length
    def period_comparison
      duration = @to - @from
      prev_from = @from - duration
      prev_to = @from
      current = period_stats(@from, @to)
      previous = period_stats(prev_from, prev_to)
      { current: current, previous: previous, changes: calculate_changes(current, previous) }
    end

    private

    def date_series
      days = ((@to.to_date - @from.to_date).to_i + 1).clamp(1, 90)
      (0...days).map { |i| @from.to_date + i.days }
    end

    def frt_values
      @tickets.where.not(first_response_at: nil)
              .pluck(:first_response_at, :created_at)
              .map { |fr, cr| ((fr - cr) / 3600.0).round(2) }
    end

    def safe_avg(values)
      return nil if values.empty?

      (values.sum / values.size).round(2)
    end

    def percentiles(values)
      sorted = values.sort
      return {} if sorted.empty?

      { p50: pct(sorted, 50), p75: pct(sorted, 75), p90: pct(sorted, 90),
        p95: pct(sorted, 95), p99: pct(sorted, 99) }
    end

    def pct(sorted, p)
      return sorted.first.round(2) if sorted.size == 1

      k = (p / 100.0 * (sorted.size - 1))
      f = k.floor
      c = k.ceil
      return sorted[f].round(2) if f == c

      (sorted[f] + ((k - f) * (sorted[c] - sorted[f]))).round(2)
    end

    def build_distribution(values, unit)
      return { buckets: [], stats: {} } if values.empty?

      sorted = values.sort
      {
        buckets: distribution_buckets(sorted),
        stats: { min: sorted.first, max: sorted.last, avg: safe_avg(sorted),
                 median: pct(sorted, 50), count: sorted.size, unit: unit },
        percentiles: percentiles(sorted)
      }
    end

    def distribution_buckets(sorted)
      return [] if sorted.empty?

      max_val = sorted.last
      bucket_size = [max_val / 10.0, 1].max.ceil
      buckets = []
      (0..max_val.ceil).step(bucket_size) do |start|
        range_end = start + bucket_size
        count = sorted.count { |v| v >= start && v < range_end }
        buckets << { range: "#{start}-#{range_end}", count: count } if count.positive?
      end
      buckets
    end

    def calculate_composite_score(resolution_rate:, avg_frt:, avg_resolution:, avg_csat:)
      score = 0.0
      weights = 0.0
      if resolution_rate
        score += (resolution_rate / 100.0) * 30
        weights += 30
      end
      if avg_frt&.positive?
        score += [1.0 - (avg_frt / 24.0), 0].max * 25
        weights += 25
      end
      if avg_resolution&.positive?
        score += [1.0 - (avg_resolution / 72.0), 0].max * 25
        weights += 25
      end
      if avg_csat
        score += (avg_csat / 5.0) * 20
        weights += 20
      end
      return 0 if weights.zero?

      ((score / weights) * 100).round(1)
    end

    def build_agent_ranking(agent_id, agent)
      agent_tickets = @tickets.where(assigned_to: agent_id)
      resolved = agent_tickets.where.not(resolved_at: nil)
      frts = agent_tickets.where.not(first_response_at: nil)
                          .pluck(:first_response_at, :created_at).map { |fr, cr| (fr - cr) / 3600.0 }
      res_times = resolved.pluck(:resolved_at, :created_at).map { |r, c| (r - c) / 3600.0 }
      csat = Escalated::SatisfactionRating.joins(:ticket)
                                          .where(Escalated.table_name('tickets') => { assigned_to: agent_id })
                                          .where(created_at: @from..@to)
      resolution_rate = agent_tickets.any? ? (resolved.count.to_f / agent_tickets.count * 100).round(1) : 0
      avg_frt = safe_avg(frts)
      avg_res = safe_avg(res_times)
      avg_csat_val = csat.any? ? csat.average(:rating).to_f.round(2) : nil

      {
        agent_id: agent_id,
        agent_name: agent.respond_to?(:name) ? agent.name : agent.email,
        total_tickets: agent_tickets.count, resolved_count: resolved.count,
        resolution_rate: resolution_rate, avg_frt_hours: avg_frt,
        avg_resolution_hours: avg_res, avg_csat: avg_csat_val,
        composite_score: calculate_composite_score(
          resolution_rate: resolution_rate, avg_frt: avg_frt,
          avg_resolution: avg_res, avg_csat: avg_csat_val
        )
      }
    end

    def cohort_by_tag
      Escalated::Tag.all.map do |tag|
        build_cohort_stats(tag.name, @tickets.joins(:tags).where(Escalated.table_name('tags') => { id: tag.id }))
      end
    end

    def cohort_by_department
      Escalated::Department.all.map { |dept| build_cohort_stats(dept.name, @tickets.where(department_id: dept.id)) }
    end

    def cohort_by_channel
      @tickets.distinct.pluck(:channel).compact.map { |ch| build_cohort_stats(ch, @tickets.where(channel: ch)) }
    end

    def cohort_by_type
      @tickets.distinct.pluck(:ticket_type).compact.map { |t| build_cohort_stats(t, @tickets.where(ticket_type: t)) }
    end

    def build_cohort_stats(name, scope)
      resolved = scope.where.not(resolved_at: nil)
      res_times = resolved.pluck(:resolved_at, :created_at).map { |r, c| (r - c) / 3600.0 }
      frts = scope.where.not(first_response_at: nil)
                  .pluck(:first_response_at, :created_at).map { |fr, cr| (fr - cr) / 3600.0 }
      {
        name: name, total: scope.count, resolved: resolved.count,
        resolution_rate: scope.any? ? (resolved.count.to_f / scope.count * 100).round(1) : 0,
        avg_resolution_hours: safe_avg(res_times), avg_frt_hours: safe_avg(frts),
        percentiles: { resolution: res_times.any? ? percentiles(res_times) : {},
                       frt: frts.any? ? percentiles(frts) : {} }
      }
    end

    def period_stats(from, to)
      tickets = Escalated::Ticket.where(created_at: from..to)
      resolved = tickets.where.not(resolved_at: nil)
      res_times = resolved.pluck(:resolved_at, :created_at).map { |r, c| (r - c) / 3600.0 }
      frts = tickets.where.not(first_response_at: nil)
                    .pluck(:first_response_at, :created_at).map { |fr, cr| (fr - cr) / 3600.0 }
      {
        total_created: tickets.count, total_resolved: resolved.count,
        resolution_rate: tickets.any? ? (resolved.count.to_f / tickets.count * 100).round(1) : 0,
        avg_frt_hours: safe_avg(frts), avg_resolution_hours: safe_avg(res_times),
        sla_breaches: tickets.where(sla_breached: true).count,
        percentiles: { resolution: res_times.any? ? percentiles(res_times) : {},
                       frt: frts.any? ? percentiles(frts) : {} }
      }
    end

    def calculate_changes(current, previous)
      %i[total_created total_resolved resolution_rate avg_frt_hours avg_resolution_hours sla_breaches].to_h do |key|
        cur = current[key].to_f
        prev_val = previous[key].to_f
        change = if prev_val.zero?
                   cur.positive? ? 100.0 : 0.0
                 else
                   ((cur - prev_val) / prev_val * 100).round(1)
                 end
        [key, change]
      end
    end
  end
end
