module Escalated
  class EscalationRule < ApplicationRecord
    self.table_name = Escalated.table_name("escalation_rules")

    validates :name, presence: true
    validates :conditions, presence: true
    validates :actions, presence: true

    scope :active, -> { where(is_active: true) }
    scope :ordered, -> { order(priority: :asc, created_at: :asc) }

    # conditions is a JSON column:
    # {
    #   "status": ["open", "in_progress"],
    #   "priority": ["high", "urgent", "critical"],
    #   "sla_breached": true,
    #   "unassigned_for_minutes": 30,
    #   "no_response_for_minutes": 60,
    #   "department_ids": [1, 2]
    # }
    #
    # actions is a JSON column:
    # {
    #   "change_priority": "critical",
    #   "change_status": "escalated",
    #   "assign_to_agent_id": 5,
    #   "assign_to_department_id": 2,
    #   "send_notification": true,
    #   "notification_recipients": ["admin@example.com"],
    #   "add_tags": ["escalated", "urgent"],
    #   "add_internal_note": "Auto-escalated due to SLA breach"
    # }

    def matches?(ticket)
      return false unless is_active

      check_status(ticket) &&
        check_priority(ticket) &&
        check_sla_breach(ticket) &&
        check_unassigned_duration(ticket) &&
        check_no_response_duration(ticket) &&
        check_department(ticket)
    end

    def active?
      is_active
    end

    private

    def check_status(ticket)
      return true unless conditions["status"].present?

      Array(conditions["status"]).include?(ticket.status)
    end

    def check_priority(ticket)
      return true unless conditions["priority"].present?

      Array(conditions["priority"]).include?(ticket.priority)
    end

    def check_sla_breach(ticket)
      return true unless conditions["sla_breached"]

      ticket.sla_first_response_breached? || ticket.sla_resolution_breached?
    end

    def check_unassigned_duration(ticket)
      return true unless conditions["unassigned_for_minutes"].present?
      return false if ticket.assigned_to.present?

      minutes = conditions["unassigned_for_minutes"].to_i
      ticket.created_at < minutes.minutes.ago
    end

    def check_no_response_duration(ticket)
      return true unless conditions["no_response_for_minutes"].present?

      minutes = conditions["no_response_for_minutes"].to_i
      last_reply = ticket.replies.public_replies.chronological.last

      if last_reply
        last_reply.created_at < minutes.minutes.ago
      else
        ticket.created_at < minutes.minutes.ago
      end
    end

    def check_department(ticket)
      return true unless conditions["department_ids"].present?

      Array(conditions["department_ids"]).include?(ticket.department_id)
    end
  end
end
