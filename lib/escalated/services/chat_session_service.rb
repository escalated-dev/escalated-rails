# frozen_string_literal: true

module Escalated
  module Services
    class ChatSessionService
      class << self
        def start_chat(params)
          ticket = nil
          session = nil

          ActiveRecord::Base.transaction do
            ticket = Escalated::Ticket.create!(
              subject: params[:subject] || 'Live Chat',
              description: params[:message] || 'Chat started',
              channel: 'chat',
              status: :open,
              priority: params[:priority] || Escalated.configuration.default_priority,
              guest_name: params[:name],
              guest_email: params[:email],
              department_id: params[:department_id],
              metadata: (params[:metadata] || {}).merge('source' => 'chat')
            )

            session = Escalated::ChatSession.create!(
              ticket: ticket,
              customer_session_id: params[:session_id] || SecureRandom.hex(16),
              status: 'waiting',
              metadata: params[:session_metadata]
            )
          end

          # Try to auto-assign an agent
          agent_id = ChatRoutingService.find_available_agent(department_id: params[:department_id])
          assign_agent(session, agent_id) if agent_id

          Escalated::Broadcasting.chat_started(ticket, session)

          { ticket: ticket, session: session }
        end

        def assign_agent(session, agent_id)
          session.update!(
            agent_id: agent_id,
            status: 'active',
            started_at: Time.current
          )

          ticket = session.ticket
          ticket.update!(assigned_to: agent_id, status: :in_progress)

          Escalated::Broadcasting.chat_assigned(ticket, session, agent_id)

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

          session
        end

        def transfer_chat(session, new_agent_id)
          old_agent_id = session.agent_id

          session.update!(
            agent_id: new_agent_id,
            status: 'active'
          )

          ticket = session.ticket
          ticket.update!(assigned_to: new_agent_id)

          CapacityService.new.decrement_load(old_agent_id, channel: 'chat') if old_agent_id
          CapacityService.new.increment_load(new_agent_id, channel: 'chat')

          Escalated::Broadcasting.chat_transferred(ticket, session, old_agent_id, new_agent_id)

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
      end
    end
  end
end
