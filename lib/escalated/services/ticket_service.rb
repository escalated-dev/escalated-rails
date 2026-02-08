module Escalated
  module Services
    class TicketService
      class << self
        def create(params)
          ticket = driver.create_ticket(params)

          if Escalated.configuration.notification_channels.include?(:email)
            Escalated::TicketMailer.new_ticket(ticket).deliver_later
          end

          Services::NotificationService.dispatch(:ticket_created, ticket: ticket)

          ticket
        end

        def update(ticket, params, actor:)
          driver.update_ticket(ticket, params, actor: actor)
        end

        def transition_status(ticket, new_status, actor:, note: nil)
          result = driver.transition_status(ticket, new_status, actor: actor, note: note)

          if Escalated.configuration.notification_channels.include?(:email)
            Escalated::TicketMailer.status_changed(result).deliver_later
          end

          if new_status.to_s == "resolved"
            Escalated::TicketMailer.ticket_resolved(result).deliver_later if Escalated.configuration.notification_channels.include?(:email)
          end

          Services::NotificationService.dispatch(:status_changed, ticket: result, status: new_status)

          result
        end

        def assign(ticket, agent, actor:)
          result = driver.assign_ticket(ticket, agent, actor: actor)

          if Escalated.configuration.notification_channels.include?(:email)
            Escalated::TicketMailer.ticket_assigned(result).deliver_later
          end

          Services::NotificationService.dispatch(:ticket_assigned, ticket: result, agent: agent)

          result
        end

        def unassign(ticket, actor:)
          driver.unassign_ticket(ticket, actor: actor)
        end

        def reply(ticket, params)
          reply = driver.add_reply(ticket, params)

          if !params[:is_internal] && Escalated.configuration.notification_channels.include?(:email)
            Escalated::TicketMailer.reply_received(ticket, reply).deliver_later
          end

          Services::NotificationService.dispatch(:reply_added, ticket: ticket, reply: reply)

          reply
        end

        def find(id)
          driver.get_ticket(id)
        end

        def list(filters = {})
          driver.list_tickets(filters)
        end

        def add_tags(ticket, tag_ids, actor:)
          driver.add_tags(ticket, tag_ids, actor: actor)
        end

        def remove_tags(ticket, tag_ids, actor:)
          driver.remove_tags(ticket, tag_ids, actor: actor)
        end

        def change_department(ticket, department, actor:)
          driver.change_department(ticket, department, actor: actor)
        end

        def change_priority(ticket, new_priority, actor:)
          result = driver.change_priority(ticket, new_priority, actor: actor)

          Services::NotificationService.dispatch(:priority_changed, ticket: result, priority: new_priority)

          result
        end

        def close(ticket, actor:)
          transition_status(ticket, :closed, actor: actor)
        end

        def reopen(ticket, actor:)
          transition_status(ticket, :reopened, actor: actor)
        end

        def resolve(ticket, actor:)
          transition_status(ticket, :resolved, actor: actor)
        end

        private

        def driver
          Escalated.driver
        end
      end
    end
  end
end
