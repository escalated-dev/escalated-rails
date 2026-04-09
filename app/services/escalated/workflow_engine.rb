# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module Escalated
  class WorkflowEngine
    OPERATORS = %w[equals not_equals contains not_contains starts_with ends_with
                   greater_than less_than greater_or_equal less_or_equal is_empty is_not_empty].freeze

    ACTION_TYPES = %w[change_status assign_agent change_priority add_tag remove_tag
                      set_department add_note send_webhook set_type delay
                      add_follower send_notification].freeze

    def process_event(event_name, ticket, context = {})
      workflows = Escalated::Workflow.for_event(event_name)
      workflows.each do |workflow|
        process_workflow(workflow, ticket, event_name, context)
      end
    end

    def dry_run(workflow, ticket)
      matched = evaluate_conditions(workflow.conditions, ticket)
      actions_preview = workflow.actions.map do |action|
        { type: action['type'], value: interpolate_variables(action['value'].to_s, ticket), would_execute: matched }
      end
      { matched: matched, actions: actions_preview }
    end

    def process_delayed_actions
      Escalated::DelayedAction.pending.find_each do |delayed|
        ticket = delayed.ticket
        execute_single_action(delayed.action_data, ticket, delayed.workflow)
        delayed.update!(executed: true)
      rescue StandardError => e
        Rails.logger.error("Escalated delayed action failed: #{e.message}")
      end
    end

    def evaluate_conditions(conditions, ticket)
      if conditions.is_a?(Hash)
        if conditions.key?('all')
          conditions['all'].all? { |c| evaluate_single_condition(c, ticket) }
        elsif conditions.key?('any')
          conditions['any'].any? { |c| evaluate_single_condition(c, ticket) }
        else
          evaluate_single_condition(conditions, ticket)
        end
      elsif conditions.is_a?(Array)
        conditions.all? { |c| evaluate_single_condition(c, ticket) }
      else
        false
      end
    end

    private

    def process_workflow(workflow, ticket, event_name, context)
      matched = evaluate_conditions(workflow.conditions, ticket)
      unless matched
        log_execution(workflow, ticket, event_name, 'skipped', [])
        return
      end

      executed_actions = execute_actions(workflow, ticket, context)
      log_execution(workflow, ticket, event_name, 'success', executed_actions)
    rescue StandardError => e
      log_execution(workflow, ticket, event_name, 'failure', [], e.message)
      Rails.logger.error("Escalated workflow #{workflow.id} failed: #{e.message}")
    end

    def evaluate_single_condition(condition, ticket)
      field = condition['field'].to_s
      operator = condition['operator'] || 'equals'
      expected = condition['value']
      actual = resolve_field(field, ticket)

      apply_operator(operator, actual, expected)
    end

    def resolve_field(field, ticket)
      case field
      when 'status' then ticket.status
      when 'priority' then ticket.priority
      when 'assigned_to' then ticket.assigned_to
      when 'department_id' then ticket.department_id
      when 'channel' then ticket.channel
      when 'ticket_type' then ticket.ticket_type
      when 'subject' then ticket.subject
      when 'description' then ticket.description
      when 'tags' then ticket.tags.pluck(:name).join(',')
      when 'hours_since_created' then ((Time.current - ticket.created_at) / 3600.0).round(1)
      when 'hours_since_updated' then ((Time.current - ticket.updated_at) / 3600.0).round(1)
      when 'sla_breached' then ticket.sla_breached
      end
    end

    def apply_operator(operator, actual, expected)
      actual_s = actual.to_s
      expected_s = expected.to_s

      case operator
      when 'equals' then actual_s == expected_s
      when 'not_equals' then actual_s != expected_s
      when 'contains' then actual_s.include?(expected_s)
      when 'not_contains' then actual_s.exclude?(expected_s)
      when 'starts_with' then actual_s.start_with?(expected_s)
      when 'ends_with' then actual_s.end_with?(expected_s)
      when 'greater_than' then actual.to_f > expected.to_f
      when 'less_than' then actual.to_f < expected.to_f
      when 'greater_or_equal' then actual.to_f >= expected.to_f
      when 'less_or_equal' then actual.to_f <= expected.to_f
      when 'is_empty' then actual_s.blank?
      when 'is_not_empty' then actual_s.present?
      else false
      end
    end

    def execute_actions(workflow, ticket, _context)
      executed = []
      workflow.actions.each do |action|
        result = execute_single_action(action, ticket, workflow)
        executed << { type: action['type'], result: result }
      end
      executed
    end

    def execute_single_action(action, ticket, workflow)
      action_type = action['type'].to_s
      value = action['value']

      case action_type
      when 'change_status'
        ticket.update!(status: value)
      when 'assign_agent'
        ticket.update!(assigned_to: value.to_i)
      when 'change_priority'
        ticket.update!(priority: value)
      when 'add_tag'
        tag = Escalated::Tag.find_or_create_by!(name: value)
        ticket.tags << tag unless ticket.tags.include?(tag)
      when 'remove_tag'
        tag = Escalated::Tag.find_by(name: value)
        ticket.tags.delete(tag) if tag
      when 'set_department'
        ticket.update!(department_id: value.to_i)
      when 'add_note'
        ticket.replies.create!(body: interpolate_variables(value.to_s, ticket), is_internal: true)
      when 'send_webhook'
        send_webhook(action, ticket)
      when 'set_type'
        ticket.update!(ticket_type: value)
      when 'delay'
        delay_minutes = value.to_i
        remaining = action['remaining_actions'] || []
        remaining.each do |remaining_action|
          Escalated::DelayedAction.create!(
            workflow: workflow, ticket: ticket,
            action_data: remaining_action,
            execute_at: delay_minutes.minutes.from_now
          )
        end
        return 'delayed'
      when 'add_follower'
        ticket.follow(value.to_i)
      when 'send_notification'
        # Placeholder for notification integration
        Rails.logger.info("Escalated workflow notification: #{interpolate_variables(value.to_s, ticket)}")
      end
      'executed'
    rescue StandardError => e
      Rails.logger.warn("Escalated action #{action_type} failed: #{e.message}")
      'failed'
    end

    def send_webhook(action, ticket)
      url = action['url'] || action['value']
      body = {
        event: 'workflow_action',
        ticket: { id: ticket.id, reference: ticket.reference, subject: ticket.subject, status: ticket.status },
        payload: action['payload'] ? interpolate_variables(action['payload'].to_s, ticket) : nil
      }

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 10
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
      request.body = body.to_json
      http.request(request)
    end

    def interpolate_variables(text, ticket)
      text.gsub(/\{\{(\w+)\}\}/) do |_match|
        var = ::Regexp.last_match(1)
        case var
        when 'ticket_id' then ticket.id
        when 'ticket_ref', 'reference' then ticket.reference
        when 'subject' then ticket.subject
        when 'status' then ticket.status
        when 'priority' then ticket.priority
        when 'assignee' then ticket.assignee.respond_to?(:name) ? ticket.assignee.name : 'Unassigned'
        when 'department' then ticket.department&.name || 'None'
        when 'requester' then ticket.requester_name
        else "{{#{var}}}"
        end
      end
    end

    def log_execution(workflow, ticket, event_name, status, actions, error = nil)
      Escalated::WorkflowLog.create!(
        workflow: workflow, ticket: ticket,
        trigger_event: event_name, status: status,
        actions_executed: actions, error_message: error
      )
    end
  end
end
