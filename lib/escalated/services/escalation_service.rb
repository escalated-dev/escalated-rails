# frozen_string_literal: true

module Escalated
  module Services
    class EscalationService
      class << self
        def evaluate_all
          rules = Escalated::EscalationRule.active.ordered
          tickets = Escalated::Ticket.by_open
          escalated_tickets = []

          tickets.find_each do |ticket|
            rules.each do |rule|
              next unless rule.matches?(ticket)

              execute_actions(ticket, rule)
              escalated_tickets << { ticket: ticket, rule: rule }
              break # Only apply the first matching rule per ticket
            end
          end

          escalated_tickets
        end

        def evaluate_ticket(ticket)
          rules = Escalated::EscalationRule.active.ordered

          rules.each do |rule|
            if rule.matches?(ticket)
              execute_actions(ticket, rule)
              return rule
            end
          end

          nil
        end

        def execute_actions(ticket, rule)
          actions = rule.actions
          return unless actions.is_a?(Hash)

          events = []

          ActiveRecord::Base.transaction do
            change_priority_action(ticket, actions['change_priority'], events) if actions['change_priority']
            change_status_action(ticket, actions['change_status'], events) if actions['change_status']
            assign_agent_action(ticket, actions['assign_to_agent_id'], events) if actions['assign_to_agent_id']
            if actions['assign_to_department_id']
              assign_department_action(ticket, actions['assign_to_department_id'], events)
            end
            add_tags_action(ticket, actions['add_tags']) if actions['add_tags']
            add_note_action(ticket, actions['add_internal_note']) if actions['add_internal_note']

            log_escalation(ticket, rule)
          end

          # Announced once committed, through the dispatch TicketService uses, so
          # workflows, webhooks, followers and plugin hooks hear about a rule's
          # changes the way they hear about an agent's.
          events.each { |event, payload| NotificationService.dispatch(event, payload) }

          send_escalation_email(ticket, rule) if actions['send_notification']

          # Every escalation, not only the ones that also send an email.
          NotificationService.dispatch(:ticket_escalated, {
                                         ticket: ticket,
                                         rule: rule,
                                         recipients: actions['notification_recipients']
                                       })

          ActiveSupport::Notifications.instrument('escalated.ticket.escalated', {
                                                    ticket: ticket,
                                                    rule: rule
                                                  })
        end

        private

        def change_priority_action(ticket, new_priority, events = [])
          old_priority = ticket.priority
          ticket.update!(priority: new_priority)

          ticket.activities.create!(
            action: 'priority_changed',
            causer: nil,
            details: { from: old_priority, to: new_priority, reason: 'escalation_rule' }
          )

          events << [:priority_changed,
                     { ticket: ticket, priority: new_priority, old_priority: old_priority, actor: nil }]
        end

        def change_status_action(ticket, new_status, events = [])
          old_status = ticket.status
          ticket.update!(status: new_status)

          ticket.activities.create!(
            action: 'status_changed',
            causer: nil,
            details: { from: old_status, to: new_status, reason: 'escalation_rule' }
          )

          events << [:status_changed, { ticket: ticket, status: new_status, old_status: old_status, actor: nil }]
        end

        def assign_agent_action(ticket, agent_id, events = [])
          agent = Escalated.configuration.user_model.find_by(id: agent_id)
          return unless agent

          old_assignee = ticket.assigned_to
          ticket.update!(assigned_to: agent.id)

          ticket.activities.create!(
            action: 'ticket_assigned',
            causer: nil,
            details: { from_agent_id: old_assignee, to_agent_id: agent.id, reason: 'escalation_rule' }
          )

          events << [:ticket_assigned, { ticket: ticket, agent: agent, actor: nil }]
        end

        def assign_department_action(ticket, department_id, events = [])
          department = Escalated::Department.find_by(id: department_id)
          return unless department

          previous = ticket.department
          old_department = ticket.department_id
          ticket.update!(department_id: department.id)

          ticket.activities.create!(
            action: 'department_changed',
            causer: nil,
            details: { from_department_id: old_department, to_department_id: department.id, reason: 'escalation_rule' }
          )

          events << [:department_changed,
                     { ticket: ticket, department: department, old_department: previous, actor: nil }]
        end

        def add_tags_action(ticket, tag_names)
          return unless tag_names.is_a?(Array)

          tag_names.each do |name|
            tag = Escalated::Tag.find_or_create_by!(name: name) do |t|
              t.slug = name.parameterize
            end
            ticket.tags << tag unless ticket.tags.include?(tag)
          end
        end

        def add_note_action(ticket, note_body)
          ticket.replies.create!(
            body: note_body,
            author: nil,
            is_internal: true,
            is_system: true
          )
        end

        def log_escalation(ticket, rule)
          ticket.activities.create!(
            action: 'ticket_escalated',
            causer: nil,
            details: {
              rule_id: rule.id,
              rule_name: rule.name,
              actions_applied: rule.actions.keys
            }
          )
        end

        def send_escalation_email(ticket, rule)
          return unless Escalated.configuration.notification_channels.include?(:email)

          Escalated::TicketMailer.ticket_escalated(ticket, rule).deliver_later
        end
      end
    end
  end
end
