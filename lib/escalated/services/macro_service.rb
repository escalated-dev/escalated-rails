module Escalated
  module Services
    class MacroService
      class << self
        def apply(macro, ticket, actor:)
          actions = macro.actions || []

          actions.each do |action|
            action = action.with_indifferent_access if action.respond_to?(:with_indifferent_access)
            type = action["type"] || action[:type]
            value = action["value"] || action[:value]

            case type.to_s
            when "status"
              TicketService.transition_status(ticket, value, actor: actor)
            when "priority"
              TicketService.change_priority(ticket, value, actor: actor)
            when "assign"
              agent = Escalated.configuration.user_model.find(value)
              AssignmentService.assign(ticket, agent, actor: actor)
            when "tags"
              tag_ids = Array(value)
              TicketService.add_tags(ticket, tag_ids, actor: actor)
            when "department"
              department = Escalated::Department.find(value)
              TicketService.change_department(ticket, department, actor: actor)
            when "reply"
              TicketService.reply(ticket, {
                body: value.to_s,
                author: actor,
                is_internal: false
              })
            when "note"
              TicketService.reply(ticket, {
                body: value.to_s,
                author: actor,
                is_internal: true
              })
            end

            ticket.reload
          end

          ticket
        end
      end
    end
  end
end
