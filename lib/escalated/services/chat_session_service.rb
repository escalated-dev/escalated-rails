# frozen_string_literal: true

module Escalated
  module Services
    class ChatSessionService
      class << self
        def start_chat(params)
          ticket = nil
          session = nil

          ActiveRecord::Base.transaction do
            # TicketService rather than Ticket.create! so the chat ticket gets
            # its SLA and contact; ticket_created is announced after commit.
            ticket = TicketService.create_local({
                                                  subject: params[:subject] || 'Live Chat',
                                                  description: params[:message] || 'Chat started',
                                                  channel: 'chat',
                                                  priority: params[:priority] ||
                                                            Escalated.configuration.default_priority,
                                                  guest_name: params[:name],
                                                  guest_email: params[:email],
                                                  department_id: params[:department_id],
                                                  metadata: (params[:metadata] || {}).merge('source' => 'chat')
                                                }, announce: false)

            token, digest, expires_at = Escalated::ChatSession.issue_visitor_token
            session = Escalated::ChatSession.create!(
              ticket: ticket,
              customer_session_id: digest,
              customer_token_expires_at: expires_at,
              status: 'waiting',
              metadata: params[:session_metadata]
            )
            session.visitor_token = token
          end

          TicketService.announce_created(ticket)
          announce(:chat_started, session)

          # Try to auto-assign an agent
          agent_id = ChatRoutingService.find_available_agent(department_id: params[:department_id], ticket: ticket)
          assign_agent(session, agent_id) if agent_id

          Escalated::Broadcasting.chat_started(ticket, session)

          { ticket: ticket, session: session }
        end

        def assign_agent(session, agent_id)
          raise ArgumentError, 'Agent cannot access this ticket' unless TicketAccess.eligible_agent?(agent_id,
                                                                                                     session.ticket)

          session.update!(
            agent_id: agent_id,
            status: 'active',
            started_at: Time.current
          )

          ticket = session.ticket
          ticket.update!(assigned_to: agent_id, status: :in_progress)

          Escalated::Broadcasting.chat_assigned(ticket, session, agent_id)
          announce(:chat_assigned, session, agent_id: agent_id.to_s)

          session
        end

        def end_chat(session, ended_by: nil)
          session.update!(
            status: 'ended',
            ended_at: Time.current
          )

          ticket = session.ticket
          ticket.update!(
            status: :resolved,
            resolved_at: Time.current,
            chat_ended_at: Time.current
          )

          CapacityService.new.decrement_load(session.agent_id, channel: 'chat') if session.agent_id

          Escalated::Broadcasting.chat_ended(ticket, session)
          announce(:chat_ended, session)

          session
        end

        # As escalated-laravel's ChatSessionService::transferChat: an agent
        # takes the chat and its ticket; a department takes the ticket, and
        # without an agent the chat goes back to the queue (unassigned,
        # waiting) and is routed again for that department.
        def transfer_chat(session, new_agent_id = nil, department_id: nil)
          new_agent_id = new_agent_id.presence
          department_id = department_id.presence
          raise ArgumentError, 'Provide an agent or a department' if new_agent_id.nil? && department_id.nil?
          if new_agent_id && !TicketAccess.eligible_agent?(new_agent_id, session.ticket)
            raise ArgumentError, 'Agent cannot access this ticket'
          end

          old_agent_id = session.agent_id
          ticket = session.ticket
          ticket.update!(department_id: department_id) if department_id

          capacity = CapacityService.new
          capacity.decrement_load(old_agent_id, channel: 'chat') if old_agent_id
          if new_agent_id
            session.update!(agent_id: new_agent_id, status: 'active')
            ticket.update!(assigned_to: new_agent_id)
            capacity.increment_load(new_agent_id, channel: 'chat')
          else
            session.update!(agent_id: nil, status: 'waiting')
            ticket.update!(assigned_to: nil)
          end

          Escalated::Broadcasting.chat_transferred(ticket, session, old_agent_id, new_agent_id)
          announce(:chat_transferred, session, previous_agent_id: old_agent_id&.to_s, agent_id: new_agent_id&.to_s,
                                               department_id: department_id&.to_s)

          unless new_agent_id
            routed = ChatRoutingService.find_available_agent(department_id: department_id, ticket: ticket)
            assign_agent(session, routed) if routed
          end

          session
        end

        def send_message(session, body:, author: nil, is_internal: false)
          ticket = session.ticket

          reply = Escalated::Reply.create!(
            ticket: ticket,
            body: body,
            author: author,
            is_internal: is_internal,
            is_system: false,
            is_pinned: false
          )

          Escalated::Broadcasting.chat_message(ticket, session, reply)
          announce(:chat_message, session, reply: reply)

          reply
        end

        def update_typing(session, is_agent:)
          if is_agent
            session.update!(agent_typing_at: Time.current)
          else
            session.update!(customer_typing_at: Time.current)
          end

          Escalated::Broadcasting.chat_typing(session.ticket, session, is_agent: is_agent)
        end

        def rate_chat(session, rating:, comment: nil)
          session.update!(
            rating: rating,
            rating_comment: comment
          )

          session
        end

        private

        # chat.started, chat.assigned, chat.transferred, chat.message and
        # chat.ended, through the dispatch tickets use, so webhooks and
        # workflows hear about them. The session's id, never its customer
        # token, goes in the payload.
        def announce(event, session, extra = {})
          NotificationService.dispatch(event, { ticket: session.ticket, chat_session_id: session.id }.merge(extra))
        end
      end
    end
  end
end
