# frozen_string_literal: true

module Escalated
  class ReportingService
    # The figures behind the dashboard and its Agents, SLA and CSAT screens,
    # and the per-agent detail, in the shapes escalated-laravel's
    # ReportingService hands those screens. Everything is over the service's
    # window (@from..@to) unless it says otherwise.
    module SubReports
      # Tickets raised per day, for the days that had any: [{ label:, value: }].
      def daily_volume
        @tickets.pluck(:created_at).map { |at| at.in_time_zone.to_date.iso8601 }.tally.sort.map do |date, count|
          { label: date, value: count }
        end
      end

      # All tickets by status and by priority, as Laravel counts them: not
      # limited to the window.
      def status_counts
        Escalated::Ticket.group(:status).count.map { |status, count| { label: status.to_s, value: count } }
      end

      def priority_counts
        Escalated::Ticket.group(:priority).count.map { |priority, count| { label: priority.to_s, value: count } }
      end

      def average_response_hours
        round1(average(hours_between(@tickets, :first_response_at))) || 0.0
      end

      def average_resolution_hours
        round1(average(hours_between(@tickets, :resolved_at))) || 0.0
      end

      # The share of tickets under an SLA policy that met it. 100 when none were.
      def sla_compliance_rate
        tickets = @tickets.where.not(sla_policy_id: nil).to_a
        return 100.0 if tickets.empty?

        breached = tickets.count { |t| sla_breached?(t) }
        ((tickets.size - breached).to_f / tickets.size * 100).round(1)
      end

      def sla_compliance_by_policy
        tickets = @tickets.where.not(sla_policy_id: nil).to_a.group_by(&:sla_policy_id)

        Escalated::SlaPolicy.active.order(:name).map do |policy|
          rows = tickets.fetch(policy.id, [])
          breached = rows.count { |t| sla_breached?(t) }
          { policy_name: policy.name, total: rows.size, met: rows.size - breached, breached: breached }
        end
      end

      # The tickets that missed an SLA, newest first, at most 100.
      def sla_breach_details
        candidates = @tickets.where(sla_breached: true)
                             .or(@tickets.where.not(sla_first_response_due_at: nil))
                             .or(@tickets.where.not(sla_resolution_due_at: nil))
                             .includes(:sla_policy)
                             .order(created_at: :desc, id: :desc)

        candidates.select { |t| sla_breached?(t) }.first(100).map do |ticket|
          {
            id: ticket.id,
            reference: ticket.reference,
            subject: ticket.subject,
            assigned_to: ticket.assigned_to,
            sla_policy_id: ticket.sla_policy_id,
            sla_policy: ticket.sla_policy && { id: ticket.sla_policy.id, name: ticket.sla_policy.name },
            sla_first_response_breached: first_response_breached?(ticket),
            sla_resolution_breached: resolution_breached?(ticket),
            first_response_at: ticket.first_response_at&.iso8601,
            resolved_at: ticket.resolved_at&.iso8601,
            created_at: ticket.created_at&.iso8601
          }
        end
      end

      def csat_average
        round1(ratings.average(:rating)&.to_f) || 0.0
      end

      def ratings_count
        ratings.count(:id)
      end

      def tickets_count
        @tickets.count(:id)
      end

      # Per assigned agent: [{ agent_id, agent_name, total_tickets,
      # resolved_tickets, avg_response_hours, avg_resolution_hours }].
      def agent_performance_rows
        assigned = @tickets.where.not(assigned_to: nil).to_a.group_by(&:assigned_to)
        names = agent_names(assigned.keys)

        assigned.map do |agent_id, tickets|
          {
            agent_id: agent_id,
            agent_name: names[agent_id.to_s],
            total_tickets: tickets.size,
            resolved_tickets: tickets.count(&:resolved_at),
            avg_response_hours: round1(average(ticket_hours(tickets, :first_response_at))),
            avg_resolution_hours: round1(average(ticket_hours(tickets, :resolved_at)))
          }
        end
      end

      def csat_by_agent
        rated = ratings.includes(:ticket).to_a
                       .select { |r| r.ticket&.assigned_to }
                       .group_by { |r| r.ticket.assigned_to }
        names = agent_names(rated.keys)

        rated.map do |agent_id, rows|
          {
            agent_id: agent_id,
            agent_name: names[agent_id.to_s],
            avg_rating: round1(average(rows.map(&:rating))),
            total_ratings: rows.size
          }
        end
      end

      # The day's average rating, for the days that had any.
      def csat_over_time
        ratings.pluck(:created_at, :rating)
               .group_by { |at, _| at.in_time_zone.to_date.iso8601 }
               .sort
               .map { |date, rows| { label: date, value: round1(average(rows.map(&:last))) } }
      end

      # One agent's figures over the window: what Reports/AgentDetail reads,
      # less the agent and the previous period, which the controller adds.
      def agent_figures(agent_id)
        tickets = @tickets.where(assigned_to: agent_id).order(:created_at).to_a
        response = ticket_hours(tickets, :first_response_at)
        agent_ratings = ratings.joins(:ticket).where(Escalated::Ticket.table_name => { assigned_to: agent_id })

        {
          total_tickets: tickets.size,
          resolved_tickets: tickets.count(&:resolved_at),
          avg_frt: round1(average(response)) || 0.0,
          avg_resolution: round1(average(ticket_hours(tickets, :resolved_at))) || 0.0,
          csat_score: round1(agent_ratings.average(:rating)&.to_f),
          response_percentiles: %i[p50 p75 p90 p95 p99].index_with { |p| percentile(response, p.to_s[1..].to_i) },
          productivity: agent_productivity(agent_id, tickets),
          workload: tickets.map { |t| t.created_at.in_time_zone.to_date.iso8601 }.tally.sort
                           .map { |date, count| { label: date, value: count } },
          csat_breakdown: agent_ratings.pluck(:rating).tally.sort
                                       .map { |rating, count| { label: "#{rating} stars", value: count } }
        }
      end

      private

      def ratings
        Escalated::SatisfactionRating.where(created_at: @from..@to)
      end

      # Replies written and tickets resolved, per day.
      def agent_productivity(agent_id, tickets)
        replies = Escalated::Reply.where(author_id: agent_id, created_at: @from..@to).pluck(:created_at)
        days = Hash.new { |h, k| h[k] = [0, 0] }
        replies.each { |at| days[at.in_time_zone.to_date.iso8601][0] += 1 }
        tickets.each do |ticket|
          days[ticket.resolved_at.in_time_zone.to_date.iso8601][1] += 1 if ticket.resolved_at&.between?(@from, @to)
        end

        days.sort.map do |date, (written, resolved)|
          { label: date, value: written + resolved, values: [written, resolved] }
        end
      end

      def first_response_breached?(ticket)
        due = ticket.sla_first_response_due_at
        due.present? && (ticket.first_response_at || Time.current) > due
      end

      def resolution_breached?(ticket)
        due = ticket.sla_resolution_due_at
        due.present? && (ticket.resolved_at || Time.current) > due
      end

      def sla_breached?(ticket)
        ticket.sla_breached || first_response_breached?(ticket) || resolution_breached?(ticket)
      end

      def hours_between(scope, stamp)
        scope.where.not(stamp => nil).pluck(stamp, :created_at).map { |at, created| (at - created) / 3600.0 }
      end

      def ticket_hours(tickets, stamp)
        tickets.filter_map { |t| t.public_send(stamp) && ((t.public_send(stamp) - t.created_at) / 3600.0) }
      end

      def average(values)
        values = values.compact
        values.empty? ? nil : values.sum.to_f / values.size
      end

      def round1(value)
        value&.round(1)
      end

      def percentile(values, p)
        sorted = values.sort
        return 0.0 if sorted.empty?

        pct(sorted, p).round(1)
      end

      def agent_names(ids)
        return {} if ids.empty?

        Escalated.configuration.user_model.where(id: ids).to_h do |user|
          [user.id.to_s, user.respond_to?(:name) && user.name.present? ? user.name : user.email]
        end
      end
    end
  end
end
