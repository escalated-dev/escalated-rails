# frozen_string_literal: true

require 'securerandom'

module Escalated
  module Services
    # The agents' in-app notifications (ADR 2026-11-05-agent-panel-data,
    # section 4), in the escalated_notifications table. On unless
    # config.agent_notifications is false.
    module AgentNotificationFeed
      PER_PAGE = 20
      MAX_PER_PAGE = 50
      TYPES = %w[ticket_assigned ticket_reply mention sla_warning sla_breached chat_transferred].freeze

      class << self
        def available?
          Escalated.configuration.agent_notifications != false
        end

        # Stores a notification for an agent, unless they caused it, and
        # broadcasts it on their channel while broadcasting is on.
        def notify(agent_id, type, ticket, data: {}, causer_id: nil)
          return unless available?
          return if agent_id.blank?
          return if causer_id.present? && causer_id.to_s == agent_id.to_s

          row = Escalated::AgentNotification.create!(
            id: SecureRandom.uuid,
            user_id: agent_id,
            type: type,
            data: data.merge('ticket_id' => ticket&.id, 'reference' => ticket&.reference).stringify_keys,
            created_at: Time.current
          )
          broadcast(agent_id, row)
          row
        end

        # Turns an engine event (NotificationService.dispatch) into notifications.
        def deliver(event, payload)
          return unless available?

          ticket = payload[:ticket]
          case event.to_sym
          when :ticket_assigned
            agent = payload[:agent]
            notify(agent&.id, 'ticket_assigned', ticket, causer_id: payload[:actor]&.id) if agent
          when :reply_added
            reply = payload[:reply]
            return unless reply && TicketReads.customer_side?(reply)

            recipients = [ticket.assigned_to, *ticket.followers.pluck(:id)].compact.map(&:to_s).uniq
            author_id = reply.author&.id
            recipients.each { |id| notify(id, 'ticket_reply', ticket, causer_id: author_id) }
          when :sla_warning
            notify(ticket&.assigned_to, 'sla_warning', ticket, data: { 'sla_type' => payload[:warning_type].to_s })
          when :sla_breached
            notify(ticket&.assigned_to, 'sla_breached', ticket, data: { 'sla_type' => payload[:breach_type].to_s })
          when :chat_transferred
            notify(payload[:agent_id], 'chat_transferred', ticket,
                   data: { 'session_id' => payload[:chat_session_id] }, causer_id: payload[:previous_agent_id])
          end
        rescue StandardError => e
          Rails.logger.warn("[Escalated::AgentNotificationFeed] #{event}: #{e.message}")
        end

        def unread_count(user)
          Escalated::AgentNotification.for_user(user.id).unread.count
        end

        # Feed items for `user`. A ticket they can no longer see (visibility,
        # department, deleted) redacts the item instead of dropping it.
        def present(rows, user)
          ids = rows.filter_map { |row| row.data.is_a?(Hash) ? row.data['ticket_id'] : nil }.uniq
          tickets = if ids.empty?
                      {}
                    else
                      Escalated::TicketAccess.apply(Escalated::Ticket.unscoped.where(id: ids), user)
                                             .select(:id, :reference, :subject).index_by(&:id)
                    end
          rows.map { |row| item(row, tickets) }
        end

        def item(row, tickets)
          data = row.data.is_a?(Hash) ? row.data : {}
          ticket_id = data['ticket_id']
          ticket = ticket_id && tickets[ticket_id.to_i]
          base = {
            id: row.id.to_s,
            type: row.type,
            created_at: row.created_at&.iso8601,
            read_at: row.read_at&.iso8601
          }
          if ticket_id && ticket.nil?
            return base.merge(title: I18n.t('escalated.agent_notifications.unavailable'), body: nil, ticket: nil,
                              url: nil)
          end

          key = TYPES.include?(row.type) ? row.type : 'generic'
          title = I18n.t("escalated.agent_notifications.#{key}",
                         reference: ticket&.reference || data['reference'].to_s, name: data['mentioned_by'].to_s)
          base.merge(
            title: title,
            body: ticket&.subject,
            ticket: ticket && { id: ticket.id, reference: ticket.reference, subject: ticket.subject },
            url: ticket && ticket_url(ticket)
          )
        end

        private

        def ticket_url(ticket)
          entry = Escalated::RouteList.routes['escalated.agent.tickets.show']
          entry && "/#{entry[:uri].sub('{id}', ERB::Util.url_encode(ticket.reference))}"
        end

        def broadcast(agent_id, row)
          return unless Escalated::Broadcasting.enabled?

          user = Escalated.configuration.user_model.find_by(id: agent_id)
          return unless user

          Escalated::Broadcasting.broadcast(Escalated::Broadcasting.agent_channel(agent_id), 'notification.created',
                                            item(row, present_tickets(row, user)))
        end

        def present_tickets(row, user)
          id = row.data['ticket_id']
          return {} unless id

          Escalated::TicketAccess.apply(Escalated::Ticket.unscoped.where(id: id), user).index_by(&:id)
        end
      end
    end
  end
end
