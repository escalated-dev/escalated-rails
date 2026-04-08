# frozen_string_literal: true

module Escalated
  module Broadcasting
    class << self
      def enabled?
        Escalated::EscalatedSetting.get_bool('broadcasting_enabled', default: false)
      end

      def broadcast(channel, event, data)
        return unless enabled?

        payload = {
          event: event.to_s,
          data: data,
          timestamp: Time.current.iso8601
        }

        ActionCable.server.broadcast(channel, payload)
      rescue StandardError => e
        Rails.logger.warn("[Escalated::Broadcasting] Failed to broadcast #{event} to #{channel}: #{e.message}")
      end

      def ticket_channel(ticket)
        "escalated_ticket_#{ticket.respond_to?(:id) ? ticket.id : ticket}"
      end

      def agent_channel(agent_id = nil)
        agent_id ? "escalated_agent_#{agent_id}" : 'escalated_agents'
      end

      # Broadcast events

      def ticket_created(ticket)
        broadcast(agent_channel, :ticket_created, ticket_payload(ticket))
      end

      def ticket_updated(ticket)
        broadcast(ticket_channel(ticket), :ticket_updated, ticket_payload(ticket))
        broadcast(agent_channel, :ticket_updated, ticket_payload(ticket))
      end

      def ticket_status_changed(ticket, old_status, new_status)
        data = ticket_payload(ticket).merge(
          old_status: old_status.to_s,
          new_status: new_status.to_s
        )
        broadcast(ticket_channel(ticket), :ticket_status_changed, data)
        broadcast(agent_channel, :ticket_status_changed, data)
      end

      def reply_created(ticket, reply)
        data = {
          ticket_id: ticket.id,
          ticket_reference: ticket.reference,
          reply_id: reply.id,
          is_internal: reply.is_internal,
          author: if reply.author
                    { id: reply.author.id,
                      name: reply.author.respond_to?(:name) ? reply.author.name : reply.author.email }
                  end
        }
        broadcast(ticket_channel(ticket), :reply_created, data)
      end

      def ticket_assigned(ticket, agent)
        data = ticket_payload(ticket).merge(
          assigned_to: if agent
                         { id: agent.id, name: agent.respond_to?(:name) ? agent.name : agent.email }
                       end
        )
        broadcast(ticket_channel(ticket), :ticket_assigned, data)
        broadcast(agent_channel(agent&.id), :ticket_assigned, data) if agent
      end

      def ticket_escalated(ticket)
        broadcast(ticket_channel(ticket), :ticket_escalated, ticket_payload(ticket))
        broadcast(agent_channel, :ticket_escalated, ticket_payload(ticket))
      end

      # Chat events

      def chat_channel(ticket)
        "escalated_chat_#{ticket.respond_to?(:id) ? ticket.id : ticket}"
      end

      def chat_started(ticket, session)
        data = chat_payload(ticket, session)
        broadcast(agent_channel, :chat_started, data)
        broadcast(chat_channel(ticket), :chat_started, data)
      end

      def chat_assigned(ticket, session, agent_id)
        data = chat_payload(ticket, session).merge(agent_id: agent_id)
        broadcast(chat_channel(ticket), :chat_assigned, data)
        broadcast(agent_channel(agent_id), :chat_assigned, data)
        broadcast(agent_channel, :chat_assigned, data)
      end

      def chat_message(ticket, session, reply)
        data = chat_payload(ticket, session).merge(
          reply_id: reply.id,
          body: reply.body,
          is_internal: reply.is_internal,
          author: if reply.author
                    { id: reply.author.id,
                      name: reply.author.respond_to?(:name) ? reply.author.name : reply.author.email }
                  end
        )
        broadcast(chat_channel(ticket), :chat_message, data)
      end

      def chat_typing(ticket, session, is_agent:)
        data = chat_payload(ticket, session).merge(is_agent: is_agent)
        broadcast(chat_channel(ticket), :chat_typing, data)
      end

      def chat_ended(ticket, session)
        data = chat_payload(ticket, session)
        broadcast(chat_channel(ticket), :chat_ended, data)
        broadcast(agent_channel, :chat_ended, data)
      end

      def chat_transferred(ticket, session, old_agent_id, new_agent_id)
        data = chat_payload(ticket, session).merge(
          old_agent_id: old_agent_id,
          new_agent_id: new_agent_id
        )
        broadcast(chat_channel(ticket), :chat_transferred, data)
        broadcast(agent_channel(old_agent_id), :chat_transferred, data) if old_agent_id
        broadcast(agent_channel(new_agent_id), :chat_transferred, data)
        broadcast(agent_channel, :chat_transferred, data)
      end

      private

      def ticket_payload(ticket)
        {
          id: ticket.id,
          reference: ticket.reference,
          subject: ticket.subject,
          status: ticket.status,
          priority: ticket.priority
        }
      end

      def chat_payload(ticket, session)
        {
          ticket_id: ticket.id,
          ticket_reference: ticket.reference,
          session_id: session.id,
          session_status: session.status,
          customer_session_id: session.customer_session_id
        }
      end
    end
  end
end
