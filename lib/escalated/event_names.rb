# frozen_string_literal: true

module Escalated
  # The one vocabulary for webhooks, workflow triggers and plugin hooks
  # (escalated-developer-context decisions/2026-10-21-event-vocabulary.md).
  #
  # Only canonical names are emitted or offered in a form. Legacy names are
  # still read from stored data -- a workflow's trigger_event, a webhook's
  # subscribed events -- and treated as their canonical name.
  module EventNames
    CHAT = %w[chat.started chat.assigned chat.transferred chat.message chat.ended].freeze

    CANONICAL = (%w[
      ticket.created ticket.updated ticket.status_changed
      ticket.resolved ticket.closed ticket.reopened
      ticket.assigned ticket.unassigned ticket.escalated
      ticket.priority_changed ticket.department_changed
      ticket.tag_added ticket.tag_removed
      reply.created note.created
      sla.warning sla.breached
    ] + CHAT).freeze

    LEGACY = {
      'ticket.replied' => 'reply.created',
      'internal_note.added' => 'note.created',
      'internal_note.created' => 'note.created',
      'tag.added' => 'ticket.tag_added',
      'ticket.tagged' => 'ticket.tag_added',
      'tag.removed' => 'ticket.tag_removed',
      'ticket.untagged' => 'ticket.tag_removed',
      'chat.session_started' => 'chat.started',
      'chat.session_ended' => 'chat.ended'
    }.freeze

    # NotificationService event => canonical name. reply_added and
    # status_changed depend on the payload; see .for_notification.
    NOTIFICATIONS = {
      ticket_created: 'ticket.created',
      ticket_updated: 'ticket.updated',
      ticket_assigned: 'ticket.assigned',
      ticket_unassigned: 'ticket.unassigned',
      priority_changed: 'ticket.priority_changed',
      department_changed: 'ticket.department_changed',
      ticket_escalated: 'ticket.escalated',
      tag_added: 'ticket.tag_added',
      tag_removed: 'ticket.tag_removed',
      sla_breached: 'sla.breached',
      sla_warning: 'sla.warning',
      chat_started: 'chat.started',
      chat_assigned: 'chat.assigned',
      chat_transferred: 'chat.transferred',
      chat_message: 'chat.message',
      chat_ended: 'chat.ended'
    }.freeze

    STATUS_EVENTS = {
      'resolved' => 'ticket.resolved', 'closed' => 'ticket.closed', 'reopened' => 'ticket.reopened'
    }.freeze

    # Every canonical name this engine produces. All of them, today.
    EMITTED = (NOTIFICATIONS.values + STATUS_EVENTS.values +
               %w[ticket.status_changed reply.created note.created]).uniq.freeze

    class << self
      # The canonical name for a stored or posted name; unknown names pass through.
      def canonical(name)
        name = name.to_s
        LEGACY.fetch(name, name)
      end

      # A canonical name and every legacy name that reads as it, for queries
      # over stored data.
      def aliases(name)
        name = canonical(name)
        [name, *LEGACY.select { |_, value| value == name }.keys]
      end

      # The canonical names a NotificationService event is announced as.
      def for_notification(event, payload)
        case event.to_sym
        when :reply_added
          reply = payload[:reply]
          [reply.respond_to?(:is_internal) && reply.is_internal ? 'note.created' : 'reply.created']
        when :status_changed
          ['ticket.status_changed', STATUS_EVENTS[payload[:status].to_s]].compact
        else
          Array(NOTIFICATIONS[event.to_sym])
        end
      end
    end
  end
end
