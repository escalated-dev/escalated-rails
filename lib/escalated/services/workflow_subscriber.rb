# frozen_string_literal: true

module Escalated
  module Services
    # Bridges the ActiveSupport::Notifications stream emitted by
    # NotificationService#instrument_event to the WorkflowEngine, the way
    # escalated-laravel's ProcessWorkflows listener does.
    #
    # A NotificationService event fires the workflows of every canonical name
    # it is announced as (Escalated::EventNames.for_notification), the same
    # names its webhooks are sent under: a public reply fires reply.created,
    # an internal note note.created, a status change to resolved both
    # ticket.status_changed and ticket.resolved.
    #
    # Subscribing during import is suppressed via ImportContext -- the
    # NotificationService already short-circuits there, but we double-
    # check inside the callback for safety.
    class WorkflowSubscriber
      PATTERN = /\Aescalated\.notification\./

      class << self
        def subscribe!
          return if @subscribed

          ActiveSupport::Notifications.subscribe(PATTERN) do |*args|
            event = ActiveSupport::Notifications::Event.new(*args)
            notification = event.name.delete_prefix('escalated.notification.')
            handle(notification, event.payload)
          end

          @subscribed = true
        end

        private

        def handle(notification, payload)
          ticket = payload[:ticket]
          return unless ticket
          return if defined?(Escalated::Support::ImportContext) && Escalated::Support::ImportContext.importing?

          Escalated::EventNames.for_notification(notification, payload).each do |workflow_event|
            Escalated::WorkflowEngine.new.process_event(workflow_event, ticket, payload.except(:ticket))
          rescue StandardError => e
            Rails.logger.warn(
              "[Escalated::WorkflowSubscriber] #{workflow_event} failed " \
              "for ticket #{ticket.respond_to?(:id) ? ticket.id : '?'}: #{e.message}"
            )
          end
        end
      end
    end
  end
end
