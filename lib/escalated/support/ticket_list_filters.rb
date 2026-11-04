# frozen_string_literal: true

module Escalated
  module Support
    # The agent ticket list's filters, applied to a ticket scope.
    #
    # The list and the agent inbox counts both go through here, so a count and
    # the list it labels cannot disagree about what a filter means.
    module TicketListFilters
      # How close a due SLA target has to be for the ticket to be "at risk".
      SLA_AT_RISK_MINUTES = 60

      BOOLEAN_VALUES = %w[0 1 true false on off yes no].freeze
      TRUE_VALUES = %w[1 true on yes].freeze
      FLAG_KEYS = %w[open sla_at_risk resolved_today].freeze
      MAX_UPDATED_WITHIN_HOURS = 8760

      # The query keys the agent ticket list reads.
      KEYS = %w[status priority ticket_type assigned assigned_to unassigned department_id account_type account_id
                search sla_breached sla_at_risk resolved_today open updated_within_hours following view
                sort_by sort_dir].freeze
      SORTABLE = %w[created_at updated_at priority].freeze

      module_function

      # The list filters in a request's query string, as strings.
      def from_query(query)
        query.slice(*KEYS).transform_values { |value| value.is_a?(Array) || value.is_a?(Hash) ? value : value.to_s }
      end

      # Orders the list by `sort_by` (created_at, updated_at or priority) and `sort_dir`.
      def order(scope, filters)
        sort = SORTABLE.include?(filters['sort_by']) ? filters['sort_by'] : 'created_at'
        scope.order(sort => filters['sort_dir'].to_s.downcase == 'asc' ? :asc : :desc, id: :desc)
      end

      # The latest public reply, for the list's one-line preview. Never an internal note.
      def latest_reply_json(ticket)
        reply = ticket.latest_public_reply
        reply && { id: reply.id, body: reply.body, created_at: reply.created_at&.iso8601 }
      end

      # Field errors for the filters added for the agent panel, or {}.
      def errors(filters)
        errors = {}
        FLAG_KEYS.each do |key|
          value = filters[key]
          next if value.nil? || value.to_s.empty?
          next if BOOLEAN_VALUES.include?(value.to_s.downcase)

          errors[key] = ["The #{key.tr('_', ' ')} field must be true or false."]
        end
        hours = filters['updated_within_hours']
        if !hours.nil? && !hours.to_s.empty? &&
           (hours.to_s !~ /\A\d+\z/ || !(1..MAX_UPDATED_WITHIN_HOURS).cover?(hours.to_i))
          errors['updated_within_hours'] = ['The updated within hours field must be between 1 and 8760.']
        end
        errors
      end

      def flag?(filters, key)
        TRUE_VALUES.include?(filters[key].to_s.downcase)
      end

      def present?(filters, key)
        value = filters[key]
        !value.nil? && value.to_s != ''
      end

      def apply(scope, filters, user = nil)
        filters = filters.to_h.stringify_keys

        scope = scope.where(status: filters['status']) if present?(filters, 'status')
        scope = scope.where.not(status: %i[resolved closed]) if flag?(filters, 'open')
        scope = scope.where(priority: filters['priority']) if present?(filters, 'priority')
        scope = scope.by_ticket_type(filters['ticket_type']) if present?(filters, 'ticket_type')
        scope = scope.assigned_to(filters['assigned_to']) if present?(filters, 'assigned_to')
        scope = scope.where(department_id: filters['department_id']) if present?(filters, 'department_id')
        scope = scope.unassigned if flag?(filters, 'unassigned')
        scope = scope.breached_sla if flag?(filters, 'sla_breached')
        scope = sla_at_risk(scope) if flag?(filters, 'sla_at_risk')
        scope = scope.where(resolved_at: Time.current.beginning_of_day..) if flag?(filters, 'resolved_today')
        if present?(filters, 'updated_within_hours') && filters['updated_within_hours'].to_s =~ /\A\d+\z/
          scope = scope.where(updated_at: filters['updated_within_hours'].to_i.hours.ago..)
        end
        scope = scope.search(filters['search']) if present?(filters, 'search')
        scope = following(scope, user) if flag?(filters, 'following') && user

        # Snoozed tickets are left out unless asked for, as escalated-laravel's list does.
        if flag?(filters, 'snoozed')
          scope.snoozed
        elsif flag?(filters, 'include_snoozed')
          scope
        else
          scope.not_snoozed
        end
      end

      # Unresolved tickets whose SLA is already breached, or whose first
      # response (still unsent) or resolution falls due within the hour.
      def sla_at_risk(scope)
        soon = SLA_AT_RISK_MINUTES.minutes.from_now
        table = Escalated::Ticket.table_name
        scope.where.not(status: %i[resolved closed]).where(
          "#{table}.sla_breached = :yes " \
          "OR (#{table}.first_response_at IS NULL AND #{table}.sla_first_response_due_at <= :soon) " \
          "OR #{table}.sla_resolution_due_at <= :soon",
          yes: true, soon: soon
        )
      end

      def following(scope, user)
        followers_table = Escalated.table_name('ticket_followers')
        tickets_table = Escalated::Ticket.table_name
        followed = Escalated::Ticket
                   .joins("INNER JOIN #{followers_table} ON #{followers_table}.ticket_id = #{tickets_table}.id")
                   .where("#{followers_table}.user_id = ?", user.id)
                   .pluck(:id)
        scope.where(id: followed)
      end
    end
  end
end
