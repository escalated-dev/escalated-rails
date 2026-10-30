# frozen_string_literal: true

module Escalated
  module Services
    # Delivers the canonical events (decisions/2026-10-21-event-vocabulary.md)
    # to plugins' actions under the canonical name only, with the payload of
    # domain-model/plugin-contract.md: the subject flat at the top and again
    # under its own key, snake_case, string keys.
    #
    # Ruby plugins receive them through Escalated.hooks (only active plugins
    # are loaded, so only they have callbacks); SDK plugins through the
    # runtime bridge. A failing plugin is logged and never fails the change
    # that caused the event.
    module PluginActions
      LIFECYCLE = %w[plugin.activated plugin.deactivated plugin.uninstalling].freeze
      # How many plugin actions may nest (see guard).
      MAX_DEPTH = 3

      class << self
        def deliver(event, payload)
          Escalated::EventNames.for_notification(event, payload).each do |name|
            data = build(name, payload)
            next if data.nil?

            # A plugin's own ctx write raises events while it handles one; the
            # same action is not handed back to plugins.
            guard(name) { deliver_now(name, data) }
          end
        rescue StandardError => e
          Rails.logger.error("[Escalated::PluginActions] delivering #{event} failed: #{e.message}")
        end

        # Re-entrancy guard, after the workflow engine's: while an action is
        # being delivered to plugins, the same action (raised by a plugin's
        # own ctx write, or ctx.emit) is not delivered again, and nesting
        # stops at MAX_DEPTH. Webhooks and workflows still see every event.
        # Returns whether the block ran.
        def guard(name)
          running = (Thread.current[:escalated_plugin_actions] ||= [])
          if running.include?(name) || running.size >= MAX_DEPTH
            Rails.logger.debug { "[Escalated::PluginActions] skipped #{name}: raised while #{running.inspect} run" }
            return false
          end

          running.push(name)
          begin
            yield
          ensure
            running.pop
          end
          true
        end

        # Whether a plugin-emitted hook would impersonate a host event: a
        # canonical event, a legacy alias of one, or a lifecycle action.
        def reserved?(hook)
          hook = hook.to_s
          LIFECYCLE.include?(hook) || Escalated::EventNames::CANONICAL.include?(hook) ||
            Escalated::EventNames::LEGACY.key?(hook)
        end

        def deliver_now(name, data)
          begin
            Escalated.hooks.do_action(name, data)
          rescue StandardError => e
            Rails.logger.error("[Escalated::PluginActions] plugin action #{name} failed: #{e.message}")
          end

          begin
            bridge = Escalated.plugin_bridge
            bridge.dispatch_action(name, data) if bridge.booted?
          rescue StandardError => e
            Rails.logger.warn("[Escalated::PluginActions] SDK plugin action #{name} failed: #{e.message}")
          end
        end

        def build(name, payload)
          return chat(name, payload) if name.start_with?('chat.')

          if %w[reply.created note.created].include?(name)
            flat = reply(payload[:reply])
            return flat.merge('reply' => flat, 'ticket' => payload[:ticket] && ticket(payload[:ticket]))
          end

          return nil unless payload[:ticket]

          flat = ticket(payload[:ticket])
          flat.merge('ticket' => flat).merge(extras(name, payload))
        end

        def ticket(ticket)
          {
            'id' => ticket.id,
            'reference' => ticket.reference,
            'subject' => ticket.subject,
            'title' => ticket.subject,
            'description' => ticket.description,
            'status' => ticket.status&.to_s,
            'priority' => ticket.priority&.to_s,
            'channel' => field(ticket, :channel),
            'ticket_type' => field(ticket, :ticket_type),
            'department_id' => ticket.department_id,
            'assigned_to' => ticket.assigned_to,
            'requester_id' => ticket.requester_id,
            'contact_id' => field(ticket, :contact_id),
            'metadata' => ticket.metadata,
            'created_at' => ticket.created_at&.iso8601,
            'updated_at' => ticket.updated_at&.iso8601
          }
        end

        def reply(reply)
          {
            'id' => reply.id,
            'ticket_id' => reply.ticket_id,
            'body' => reply.body,
            'type' => reply_type(reply),
            'is_internal' => reply.is_internal ? true : false,
            'author_id' => reply.author_id,
            'created_at' => reply.created_at&.iso8601,
            'updated_at' => reply.updated_at&.iso8601
          }
        end

        private

        def extras(name, payload)
          case name
          when 'ticket.status_changed'
            { 'old_status' => payload[:old_status]&.to_s, 'new_status' => payload[:status]&.to_s }
          when 'ticket.assigned'
            { 'agent_id' => id_of(payload[:agent]) }
          when 'ticket.unassigned'
            { 'previous_agent_id' => payload[:previous_agent_id] }
          when 'ticket.priority_changed'
            { 'old_priority' => payload[:old_priority]&.to_s, 'new_priority' => payload[:priority]&.to_s }
          when 'ticket.department_changed'
            { 'old_department_id' => id_of(payload[:old_department]),
              'new_department_id' => id_of(payload[:department]) }
          when 'ticket.tag_added', 'ticket.tag_removed'
            tag = Escalated::Tag.find_by(id: payload[:tag_id])
            { 'tag' => { 'id' => payload[:tag_id], 'name' => payload[:tag_name], 'slug' => tag&.try(:slug) } }
          when 'sla.warning' then { 'type' => payload[:warning_type]&.to_s }
          when 'sla.breached' then { 'type' => payload[:breach_type]&.to_s }
          else {}
          end
        end

        # Never the visitor's token or email.
        def chat(name, payload)
          session = Escalated::ChatSession.find_by(id: payload[:chat_session_id])
          data = {
            'session_id' => payload[:chat_session_id],
            'ticket_id' => payload[:ticket]&.id,
            'status' => session&.status&.to_s,
            'agent_id' => session&.agent_id,
            'department_id' => payload[:ticket]&.department_id
          }
          case name
          when 'chat.assigned' then data['agent_id'] = payload[:agent_id] if payload[:agent_id]
          when 'chat.transferred'
            data['from_agent_id'] = payload[:previous_agent_id]
            data['to_agent_id'] = payload[:agent_id]
          when 'chat.message'
            data['reply_id'] = payload[:reply]&.id
          end
          { 'session' => data }
        end

        def reply_type(reply)
          return 'note' if reply.is_internal
          return 'system' if reply.respond_to?(:is_system) && reply.is_system

          'reply'
        end

        def id_of(value)
          value.respond_to?(:id) ? value.id : value
        end

        def field(record, name)
          record.respond_to?(name) ? record.public_send(name) : nil
        end
      end
    end
  end
end
