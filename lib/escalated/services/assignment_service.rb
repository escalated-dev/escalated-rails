module Escalated
  module Services
    class AssignmentService
      class << self
        def assign(ticket, agent, actor:)
          TicketService.assign(ticket, agent, actor: actor)
        end

        def unassign(ticket, actor:)
          TicketService.unassign(ticket, actor: actor)
        end

        def auto_assign(ticket)
          return nil unless ticket.department.present?

          agent = next_available_agent(ticket.department)
          return nil unless agent

          TicketService.assign(ticket, agent, actor: nil)
          agent
        end

        def round_robin(department)
          agents = department.agents.to_a
          return nil if agents.empty?

          # Find the agent with the fewest open tickets in this department
          agent_loads = agents.map do |agent|
            open_count = Escalated::Ticket
              .by_open
              .assigned_to(agent.id)
              .where(department_id: department.id)
              .count

            { agent: agent, count: open_count }
          end

          # Sort by ticket count, then by last assignment time for tie-breaking
          agent_loads.sort_by { |a| a[:count] }.first[:agent]
        end

        def reassign(ticket, new_agent, actor:)
          old_agent_id = ticket.assigned_to
          result = TicketService.assign(ticket, new_agent, actor: actor)

          ActiveSupport::Notifications.instrument("escalated.ticket.reassigned", {
            ticket: result,
            from_agent_id: old_agent_id,
            to_agent_id: new_agent.id
          })

          result
        end

        def bulk_assign(ticket_ids, agent, actor:)
          tickets = Escalated::Ticket.where(id: ticket_ids)
          results = []

          tickets.each do |ticket|
            results << TicketService.assign(ticket, agent, actor: actor)
          end

          results
        end

        def bulk_unassign(ticket_ids, actor:)
          tickets = Escalated::Ticket.where(id: ticket_ids)
          results = []

          tickets.each do |ticket|
            results << TicketService.unassign(ticket, actor: actor)
          end

          results
        end

        private

        def next_available_agent(department)
          round_robin(department)
        end
      end
    end
  end
end
