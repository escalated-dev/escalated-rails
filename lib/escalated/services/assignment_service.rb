# frozen_string_literal: true

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
          return nil if ticket.department.blank?

          agent = next_available_agent(ticket.department)
          return nil unless agent

          TicketService.assign(ticket, agent, actor: nil)
          agent
        end

        def round_robin(department)
          least_loaded(department.agents.to_a, department)
        end

        def reassign(ticket, new_agent, actor:)
          old_agent_id = ticket.assigned_to
          result = TicketService.assign(ticket, new_agent, actor: actor)

          ActiveSupport::Notifications.instrument('escalated.ticket.reassigned', {
                                                    ticket: result,
                                                    from_agent_id: old_agent_id,
                                                    to_agent_id: new_agent.id
                                                  })

          result
        end

        def bulk_assign(ticket_ids, agent, actor:)
          tickets = Escalated::Ticket.where(id: ticket_ids)
          tickets.map do |ticket|
            TicketService.assign(ticket, agent, actor: actor)
          end
        end

        def bulk_unassign(ticket_ids, actor:)
          tickets = Escalated::Ticket.where(id: ticket_ids)
          tickets.map do |ticket|
            TicketService.unassign(ticket, actor: actor)
          end
        end

        private

        def next_available_agent(department)
          agents = department.agents.to_a
          return nil if agents.empty?

          # Prefer agents who are currently available for support work (chat
          # status online or away). Offline agents are skipped so long as at
          # least one available agent exists; if nobody is available we fall
          # back to the full roster so tickets are never stranded. See issue #67.
          candidates = available_agents(agents).presence || agents
          least_loaded(candidates, department)
        end

        # Narrows a list of agent users to those whose chat presence is online
        # or away (i.e. not offline and not presence-less).
        def available_agents(agents)
          return agents if agents.empty?

          available_ids = Escalated::AgentProfile
                          .chat_available
                          .where(user_id: agents.map(&:id))
                          .pluck(:user_id)

          agents.select { |agent| available_ids.include?(agent.id) }
        end

        # Returns the agent with the fewest open tickets in the department.
        def least_loaded(agents, department)
          return nil if agents.empty?

          agent_loads = agents.map do |agent|
            open_count = Escalated::Ticket
                         .by_open
                         .assigned_to(agent.id)
                         .where(department_id: department.id)
                         .count

            { agent: agent, count: open_count }
          end

          agent_loads.min_by { |a| a[:count] }[:agent]
        end
      end
    end
  end
end
