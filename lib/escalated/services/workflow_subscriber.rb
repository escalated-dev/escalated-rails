# frozen_string_literal: true

module Escalated
  module Services
    # Bridges the ActiveSupport::Notifications stream emitted by
    # NotificationService#instrument_event to the WorkflowEngine.
    #
    # Previously the WorkflowEngine was defined but orphaned — nothing
    # invoked process_event. This subscriber mirrors the listener
    # pattern used in escalated-laravel (ProcessWorkflows) and
    # escalated-nestjs (WorkflowListener).
    #
    # Event mappings (NotificationService event name => workflow trigger):
    #   :ticket_created    => 'ticket.created'
    #   :status_changed    => 'ticket.status_changed'
    #   :ticket_assigned   => 'ticket.assigned'
    #   :priority_changed  => 'ticket.priority_changed'
    #   :reply_added       => 'ticket.replied'
    #   :ticket_escalated  => 'ticket.escalated'
    #   :sla_breached      => 'sla.breached'
    #   :sla_warning       => 'sla.warning'
    #
    # Subscribing during import is suppressed via ImportContext — the
    # NotificationService already short-circuits there, but we double-
    # check inside the callback for safety.
    class WorkflowSubscriber
      EVENT_MAP = {
        'escalated.notification.ticket_created'   => 'ticket.created',
        'escalated.notification.status_changed'   => 'ticket.status_changed',
        'escalated.notification.ticket_assigned'  => 'ticket.assigned',
        'escalated.notification.priority_changed' => 'ticket.priority_changed',
        'escalated.notification.reply_added'      => 'ticket.replied',
        'escalated.notification.ticket_escalated' => 'ticket.escalated',
        'escalated.notification.sla_breached'     => 'sla.breached',
        'escalated.notification.sla_warning'      => 'sla.warning'
      }.freeze

      class << self
        def subscribe!
          return if @subscribed

          EVENT_MAP.each do |notification, workflow_event|
            ActiveSupport::Notifications.subscribe(notification) do |*args|
              event = ActiveSupport::Notifications::Event.new(*args)
              payload = event.payload
              ticket = payload[:ticket]
              next unless ticket

              begin
                next if defined?(Escalated::Support::ImportContext) &&
                        Escalated::Support::ImportContext.importing?

                Escalated::WorkflowEngine.new.process_event(
                  workflow_event, ticket, payload.except(:ticket)
                )
              rescue StandardError => e
                Rails.logger.warn(
                  "[Escalated::WorkflowSubscriber] #{workflow_event} failed " \
                  "for ticket #{ticket.respond_to?(:id) ? ticket.id : '?'}: #{e.message}"
                )
              end
            end
          end

          @subscribed = true
        end
      end
    end
  end
end
