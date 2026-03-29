module Escalated
  class AutomationRunner
    # Evaluate all active automations against open tickets.
    # Returns the total number of tickets affected.
    def run
      automations = Escalated::Automation.active
      affected = 0

      automations.each do |automation|
        tickets = find_matching_tickets(automation)

        tickets.each do |ticket|
          execute_actions(automation, ticket)
          affected += 1
        end

        automation.update!(last_run_at: Time.current)
      end

      affected
    end

    private

    # Find open tickets matching the automation's conditions.
    def find_matching_tickets(automation)
      scope = Escalated::Ticket.by_open

      (automation.conditions || []).each do |condition|
        field    = condition["field"].to_s
        operator = condition["operator"] || ">"
        value    = condition["value"]

        case field
        when "hours_since_created"
          threshold = Time.current - value.to_i.hours
          scope = scope.where("#{Escalated::Ticket.table_name}.created_at #{resolve_operator(operator)} ?", threshold)

        when "hours_since_updated"
          threshold = Time.current - value.to_i.hours
          scope = scope.where("#{Escalated::Ticket.table_name}.updated_at #{resolve_operator(operator)} ?", threshold)

        when "hours_since_assigned"
          # Approximation: use updated_at where assigned_to is set
          threshold = Time.current - value.to_i.hours
          scope = scope.where.not(assigned_to: nil)
                       .where("#{Escalated::Ticket.table_name}.updated_at #{resolve_operator(operator)} ?", threshold)

        when "status"
          scope = scope.where(status: value)

        when "priority"
          scope = scope.where(priority: value)

        when "assigned"
          if value == "unassigned"
            scope = scope.where(assigned_to: nil)
          elsif value == "assigned"
            scope = scope.where.not(assigned_to: nil)
          end

        when "ticket_type"
          scope = scope.where(ticket_type: value)

        when "subject_contains"
          scope = scope.where("#{Escalated::Ticket.table_name}.subject LIKE ?", "%#{Escalated::Ticket.sanitize_sql_like(value.to_s)}%")
        end
      end

      scope
    end

    # Execute the automation's actions on a ticket.
    def execute_actions(automation, ticket)
      (automation.actions || []).each do |action|
        action_type = action["type"].to_s
        value       = action["value"]

        begin
          case action_type
          when "change_status"
            ticket.update!(status: value)

          when "assign"
            ticket.update!(assigned_to: value.to_i)

          when "add_tag"
            tag = Escalated::Tag.find_by(name: value)
            if tag && !ticket.tags.include?(tag)
              ticket.tags << tag
            end

          when "change_priority"
            ticket.update!(priority: value)

          when "add_note"
            ticket.replies.create!(
              body: value,
              is_internal: true,
              is_pinned: false
            )

          when "set_ticket_type"
            if Escalated::Ticket::TICKET_TYPES.include?(value)
              ticket.update!(ticket_type: value)
            end
          end
        rescue StandardError => e
          Rails.logger.warn(
            "Escalated automation action failed: " \
            "automation_id=#{automation.id} ticket_id=#{ticket.id} " \
            "action=#{action_type} error=#{e.message}"
          )
        end
      end
    end

    # Resolve a condition operator to a SQL comparison.
    # For hours_since fields, > hours means < datetime (older).
    def resolve_operator(operator)
      case operator
      when ">"  then "<"
      when ">=" then "<="
      when "<"  then ">"
      when "<=" then ">="
      when "="  then "="
      else "<"
      end
    end
  end
end
