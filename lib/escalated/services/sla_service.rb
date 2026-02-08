module Escalated
  module Services
    class SlaService
      class << self
        def attach_policy(ticket, policy = nil)
          return unless Escalated.configuration.sla_enabled?

          policy ||= find_policy_for(ticket)
          return unless policy

          ticket.update!(
            sla_policy_id: policy.id,
            sla_first_response_due_at: calculate_due_date(policy.first_response_hours_for(ticket.priority)),
            sla_resolution_due_at: calculate_due_date(policy.resolution_hours_for(ticket.priority))
          )
        end

        def check_breaches
          return unless Escalated.configuration.sla_enabled?

          breached_tickets = []

          # Check first response breaches
          Escalated::Ticket
            .by_open
            .where(sla_breached: false)
            .where.not(sla_first_response_due_at: nil)
            .where(first_response_at: nil)
            .where("sla_first_response_due_at < ?", Time.current)
            .find_each do |ticket|
              mark_breached(ticket, :first_response)
              breached_tickets << ticket
            end

          # Check resolution breaches
          Escalated::Ticket
            .by_open
            .where(sla_breached: false)
            .where.not(sla_resolution_due_at: nil)
            .where(resolved_at: nil)
            .where("sla_resolution_due_at < ?", Time.current)
            .find_each do |ticket|
              mark_breached(ticket, :resolution)
              breached_tickets << ticket
            end

          breached_tickets
        end

        def check_warnings
          return unless Escalated.configuration.sla_enabled?

          warning_tickets = []

          # First response warnings (1 hour before breach)
          Escalated::Ticket
            .by_open
            .where(sla_breached: false)
            .where.not(sla_first_response_due_at: nil)
            .where(first_response_at: nil)
            .where("sla_first_response_due_at BETWEEN ? AND ?", Time.current, 1.hour.from_now)
            .find_each do |ticket|
              warning_tickets << { ticket: ticket, type: :first_response_warning }
            end

          # Resolution warnings (2 hours before breach)
          Escalated::Ticket
            .by_open
            .where(sla_breached: false)
            .where.not(sla_resolution_due_at: nil)
            .where(resolved_at: nil)
            .where("sla_resolution_due_at BETWEEN ? AND ?", Time.current, 2.hours.from_now)
            .find_each do |ticket|
              warning_tickets << { ticket: ticket, type: :resolution_warning }
            end

          warning_tickets
        end

        def calculate_due_date(hours)
          return nil unless hours

          if Escalated.configuration.business_hours_only?
            calculate_business_hours_due_date(hours)
          else
            Time.current + hours.hours
          end
        end

        def recalculate_for_ticket(ticket)
          return unless ticket.sla_policy

          policy = ticket.sla_policy

          updates = {}
          unless ticket.first_response_at
            updates[:sla_first_response_due_at] = calculate_due_date(
              policy.first_response_hours_for(ticket.priority)
            )
          end

          unless ticket.resolved_at
            updates[:sla_resolution_due_at] = calculate_due_date(
              policy.resolution_hours_for(ticket.priority)
            )
          end

          ticket.update!(updates) if updates.any?
        end

        def stats
          return {} unless Escalated.configuration.sla_enabled?

          total = Escalated::Ticket.where.not(sla_policy_id: nil).count
          breached = Escalated::Ticket.where(sla_breached: true).count

          responded = Escalated::Ticket.where.not(first_response_at: nil, sla_first_response_due_at: nil)
          on_time_responses = responded.where("first_response_at <= sla_first_response_due_at").count

          resolved = Escalated::Ticket.where.not(resolved_at: nil, sla_resolution_due_at: nil)
          on_time_resolutions = resolved.where("resolved_at <= sla_resolution_due_at").count

          {
            total_with_sla: total,
            total_breached: breached,
            breach_rate: total > 0 ? (breached.to_f / total * 100).round(1) : 0,
            first_response_on_time: on_time_responses,
            first_response_on_time_rate: responded.count > 0 ? (on_time_responses.to_f / responded.count * 100).round(1) : 0,
            resolution_on_time: on_time_resolutions,
            resolution_on_time_rate: resolved.count > 0 ? (on_time_resolutions.to_f / resolved.count * 100).round(1) : 0
          }
        end

        private

        def find_policy_for(ticket)
          if ticket.department&.default_sla_policy_id.present?
            Escalated::SlaPolicy.find_by(id: ticket.department.default_sla_policy_id)
          else
            Escalated::SlaPolicy.default_policy.first
          end
        end

        def mark_breached(ticket, breach_type)
          ActiveRecord::Base.transaction do
            ticket.update!(sla_breached: true)

            ticket.activities.create!(
              action: "sla_breached",
              causer: nil,
              details: { breach_type: breach_type.to_s }
            )
          end

          if Escalated.configuration.notification_channels.include?(:email)
            Escalated::TicketMailer.sla_breach(ticket).deliver_later
          end

          NotificationService.dispatch(:sla_breached, ticket: ticket, breach_type: breach_type)

          ActiveSupport::Notifications.instrument("escalated.sla.breached", {
            ticket: ticket,
            breach_type: breach_type
          })
        end

        def calculate_business_hours_due_date(hours)
          bh = Escalated.configuration.business_hours
          start_hour = bh[:start] || 9
          end_hour = bh[:end] || 17
          working_days = bh[:working_days] || [1, 2, 3, 4, 5]
          tz = bh[:timezone] || "UTC"

          current_time = Time.current.in_time_zone(tz)
          remaining_hours = hours.to_f

          while remaining_hours > 0
            if working_days.include?(current_time.wday)
              day_start = current_time.change(hour: start_hour, min: 0, sec: 0)
              day_end = current_time.change(hour: end_hour, min: 0, sec: 0)

              current_time = day_start if current_time < day_start

              if current_time < day_end
                available_hours = (day_end - current_time) / 3600.0

                if remaining_hours <= available_hours
                  return current_time + remaining_hours.hours
                else
                  remaining_hours -= available_hours
                end
              end
            end

            current_time = (current_time + 1.day).change(hour: start_hour, min: 0, sec: 0)
          end

          current_time
        end
      end
    end
  end
end
