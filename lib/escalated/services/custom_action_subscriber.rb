# frozen_string_literal: true

module Escalated
  module Services
    # Records an internal note whenever a custom ticket action is triggered,
    # giving an audit trail of who ran which action. The note is authored by the
    # triggering agent, so the body need not repeat their name.
    #
    # Mirrors the Laravel RecordCustomActionInternalNote listener and the NestJS
    # RecordCustomActionInternalNoteListener.
    class CustomActionSubscriber
      NOTIFICATION = 'escalated.notification.custom_action_triggered'

      class << self
        def subscribe!
          return if @subscribed

          ActiveSupport::Notifications.subscribe(NOTIFICATION) do |*args|
            event = ActiveSupport::Notifications::Event.new(*args)
            payload = event.payload
            ticket = payload[:ticket]
            next unless ticket

            begin
              next if defined?(Escalated::Support::ImportContext) &&
                      Escalated::Support::ImportContext.importing?

              TicketService.reply(ticket, {
                                    body: %(Custom action "#{payload[:action_key]}" was triggered.),
                                    author: payload[:user],
                                    is_internal: true
                                  })
            rescue StandardError => e
              ticket_id = ticket.respond_to?(:id) ? ticket.id : '?'
              Rails.logger.warn("[Escalated::CustomActionSubscriber] failed for ticket #{ticket_id}: #{e.message}")
            end
          end

          @subscribed = true
        end
      end
    end
  end
end
