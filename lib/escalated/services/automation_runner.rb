module Escalated
  module Services
    class AutomationRunner
      def run
        affected = 0

        Escalated::Automation.active.each do |automation|
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

      def find_matching_tickets(automation)
        scope = Escalated::Ticket.where(status: [:open, :in_progress, :waiting_on_customer, :waiting_on_agent, :escalated, :reopened])

        (automation.conditions || []).each do |condition|
          field = condition["field"]
          value = condition["value"]

          case field
          when "hours_since_created"
            scope = scope.where("created_at <= ?", value.to_i.hours.ago)
          when "hours_since_updated"
            scope = scope.where("updated_at <= ?", value.to_i.hours.ago)
          when "status"
            scope = scope.where(status: value)
          when "priority"
            scope = scope.where(priority: value)
          when "assigned"
            scope = value == "unassigned" ? scope.where(assigned_to: nil) : scope.where.not(assigned_to: nil)
          end
        end

        scope
      end

      def execute_actions(automation, ticket)
        (automation.actions || []).each do |action|
          type = action["type"]
          value = action["value"]

          begin
            case type
            when "change_status" then ticket.update!(status: value)
            when "assign" then ticket.update!(assigned_to: value.to_i)
            when "add_tag"
              tag = Escalated::Tag.find_by(name: value)
              ticket.tags << tag if tag && !ticket.tags.include?(tag)
            when "change_priority" then ticket.update!(priority: value)
            when "add_note"
              Escalated::Reply.create!(ticket: ticket, body: value, is_internal: true, is_system: true, is_pinned: false)
            end
          rescue => e
            Rails.logger.warn("Escalated automation action failed: automation=#{automation.id} ticket=#{ticket.id} action=#{type} error=#{e.message}")
          end
        end
      end
    end
  end
end
