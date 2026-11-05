# frozen_string_literal: true

module Escalated
  module Services
    # Per-agent unread tracking (ADR 2026-11-05-agent-panel-data, section 1).
    #
    # A ticket is unread for an agent when the agent marked it unread, or when
    # it has customer activity (last_customer_activity_at) newer than the
    # agent's read marker, or no marker at all.
    module TicketReads
      class << self
        def mark_read(agent, ticket)
          write(agent, ticket, Time.current)
        end

        def mark_unread(agent, ticket)
          write(agent, ticket, nil)
        end

        # { ticket_id => is_unread } for the tickets, from one query.
        def flags(agent, tickets)
          tickets = Array(tickets)
          markers = if tickets.empty?
                      {}
                    else
                      Escalated::TicketRead.where(user_id: agent.id, ticket_id: tickets.map(&:id))
                                           .pluck(:ticket_id, :last_read_at).to_h
                    end

          tickets.to_h do |ticket|
            [ticket.id, unread?(ticket.last_customer_activity_at, markers.key?(ticket.id), markers[ticket.id])]
          end
        end

        # `is_unread`, `requester_online` and `requester_last_seen_at` for agent
        # rows, from one query each per page. Not in cloud mode, where tickets
        # do not live in the local table.
        def row_fields(agent, tickets)
          return {} if Escalated.configuration.cloud?

          unread = flags(agent, tickets)
          presence = CustomerPresenceTracker.lookup(tickets)
          tickets.to_h { |t| [t.id, { is_unread: unread[t.id], **presence[t.id] }] }
        end

        # Opening the ticket in the agent panel is reading it; its row fields.
        def opened(agent, ticket)
          return {} if Escalated.configuration.cloud?

          mark_read(agent, ticket)
          row_fields(agent, [ticket])[ticket.id] || {}
        end

        def unread?(activity, has_marker, last_read_at)
          return true if has_marker && last_read_at.nil?
          return false if activity.nil?
          return true unless has_marker

          activity > last_read_at
        end

        # Limits a ticket relation to the tickets unread for the agent, as two
        # EXISTS subqueries (portable across SQLite, PostgreSQL and MySQL).
        def only_unread(scope, agent)
          reads = Escalated::TicketRead.quoted_table_name
          tickets = Escalated::Ticket.quoted_table_name
          marker = "SELECT 1 FROM #{reads} tr WHERE tr.ticket_id = #{tickets}.id AND tr.user_id = :agent"
          scope.where(
            "EXISTS (#{marker} AND tr.last_read_at IS NULL) OR " \
            "(#{tickets}.last_customer_activity_at IS NOT NULL AND NOT EXISTS " \
            "(#{marker} AND tr.last_read_at >= #{tickets}.last_customer_activity_at))",
            agent: agent.id
          )
        end

        # A public reply or chat message from the customer side: the requester,
        # the ticket's contact, a guest (no author), or a host user who is not
        # staff. Agents' replies, internal notes and system messages are not.
        def customer_side?(reply)
          return false if reply.is_internal || reply.is_system || reply.try(:system_authored)

          author = reply.author
          return true if author.nil?
          return true if author.is_a?(Escalated::Contact)

          ticket = reply.ticket
          return true if ticket && ticket.requester_type == author.class.name && ticket.requester_id == author.id

          !staff?(author)
        end

        def staff?(user)
          (user.respond_to?(:escalated_agent?) && user.escalated_agent?) ||
            (user.respond_to?(:escalated_admin?) && user.escalated_admin?)
        end

        # Records a customer-side reply as activity on its ticket.
        def reply_created(reply)
          return if Escalated::Support::ImportContext.importing?
          return unless customer_side?(reply)

          Escalated::Ticket.unscoped.where(id: reply.ticket_id)
                           .update_all(last_customer_activity_at: reply.created_at || Time.current)
        end

        private

        def write(agent, ticket, at)
          marker = Escalated::TicketRead.find_or_initialize_by(user_id: agent.id, ticket_id: ticket.id)
          marker.update!(last_read_at: at)
        rescue ActiveRecord::RecordNotUnique
          Escalated::TicketRead.where(user_id: agent.id, ticket_id: ticket.id).update_all(last_read_at: at)
        end
      end
    end
  end
end
