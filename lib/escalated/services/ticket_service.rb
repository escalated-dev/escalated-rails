# frozen_string_literal: true

module Escalated
  module Services
    class TicketService
      class << self
        def create(params)
          params = resolve_contact_params(params)
          fire_hook('ticket_before_create', params)
          ticket = driver.create_ticket(params)

          if Escalated.configuration.notification_channels.include?(:email)
            Escalated::TicketMailer.new_ticket(ticket).deliver_later
          end

          Services::NotificationService.dispatch(:ticket_created, ticket: ticket)
          Escalated::Broadcasting.ticket_created(ticket)

          ticket
        end

        def update(ticket, params, actor:)
          result = driver.update_ticket(ticket, params, actor: actor)
          Services::NotificationService.dispatch(:ticket_updated, ticket: result, actor: actor)
          Escalated::Broadcasting.ticket_updated(result)
          result
        end

        def transition_status(ticket, new_status, actor:, note: nil)
          old_status = ticket.status
          result = driver.transition_status(ticket, new_status, actor: actor, note: note)

          if Escalated.configuration.notification_channels.include?(:email)
            Escalated::TicketMailer.status_changed(result).deliver_later
          end

          if (new_status.to_s == 'resolved') && Escalated.configuration.notification_channels.include?(:email)
            Escalated::TicketMailer.ticket_resolved(result).deliver_later
          end

          Services::NotificationService.dispatch(:status_changed, ticket: result, status: new_status,
                                                                  old_status: old_status, actor: actor)
          Escalated::Broadcasting.ticket_status_changed(result, old_status, new_status)

          result
        end

        def assign(ticket, agent, actor:)
          result = driver.assign_ticket(ticket, agent, actor: actor)

          if Escalated.configuration.notification_channels.include?(:email)
            Escalated::TicketMailer.ticket_assigned(result).deliver_later
          end

          Services::NotificationService.dispatch(:ticket_assigned, ticket: result, agent: agent)
          Escalated::Broadcasting.ticket_assigned(result, agent)

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
          Escalated::Broadcasting.reply_created(ticket, reply)

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
          old_department = ticket.department
          result = driver.change_department(ticket, department, actor: actor)

          Services::NotificationService.dispatch(:department_changed, ticket: result, department: department,
                                                                      old_department: old_department, actor: actor)

          result
        end

        def change_priority(ticket, new_priority, actor:)
          old_priority = ticket.priority
          result = driver.change_priority(ticket, new_priority, actor: actor)

          Services::NotificationService.dispatch(:priority_changed, ticket: result, priority: new_priority,
                                                                    old_priority: old_priority, actor: actor)

          result
        end

        def snooze_ticket(ticket, until_time, actor:)
          ticket.update!(
            status_before_snooze: Escalated::Ticket.statuses[ticket.status],
            snoozed_until: until_time,
            snoozed_by: actor.id
          )

          Services::NotificationService.dispatch(:ticket_snoozed, ticket: ticket)

          ticket
        end

        def unsnooze_ticket(ticket)
          previous_status = ticket.status_before_snooze
          ticket.update!(
            snoozed_until: nil,
            snoozed_by: nil,
            status_before_snooze: nil
          )

          if previous_status.present?
            status_key = Escalated::Ticket.statuses.key(previous_status)
            ticket.update!(status: status_key) if status_key
          end

          Services::NotificationService.dispatch(:ticket_unsnoozed, ticket: ticket)

          ticket
        end

        def split(ticket, reply, actor:)
          new_ticket = nil

          ActiveRecord::Base.transaction do
            new_ticket = driver.create_ticket(
              subject: "Split from #{ticket.reference}: #{reply.body.truncate(80)}",
              description: reply.body,
              requester: ticket.requester,
              priority: ticket.priority,
              department_id: ticket.department_id,
              tag_ids: ticket.tag_ids,
              metadata: (ticket.metadata || {}).merge('split_from' => ticket.reference)
            )

            # Link the new ticket to the original
            Escalated::TicketLink.create!(
              parent_ticket: ticket,
              child_ticket: new_ticket,
              link_type: 'parent_child'
            )

            # System note on original ticket
            Escalated::Reply.create!(
              ticket: ticket,
              body: "Reply was split into new ticket #{new_ticket.reference}.",
              is_internal: true,
              is_system: true,
              is_pinned: false
            )

            # System note on new ticket
            Escalated::Reply.create!(
              ticket: new_ticket,
              body: "This ticket was split from #{ticket.reference}.",
              is_internal: true,
              is_system: true,
              is_pinned: false
            )
          end

          Services::NotificationService.dispatch(:ticket_created, ticket: new_ticket)

          new_ticket
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

        # A plugin hook that raises is logged; it does not stop the ticket.
        def fire_hook(hook, *)
          Escalated.hooks.do_action(hook, *)
        rescue StandardError => e
          Rails.logger.error("[Escalated::TicketService] #{hook} hook failed: #{e.message}")
        end

        # Resolve/create a Contact when inline guest_email is provided
        # and no contact_id is set. Mutates a local copy of the hash
        # so callers passing symbol keys or string keys both work.
        def resolve_contact_params(params)
          params = params.dup
          # Already linked to a Contact — nothing to do.
          return params if params[:contact_id].present? || params['contact_id'].present?

          guest_email = params[:guest_email] || params['guest_email']
          return params if guest_email.blank?

          guest_name = params[:guest_name] || params['guest_name']
          contact = Escalated::Contact.find_or_create_by_email(guest_email, guest_name)
          params[:contact_id] = contact.id
          params
        end
      end
    end
  end
end
