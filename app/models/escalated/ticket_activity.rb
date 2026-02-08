module Escalated
  class TicketActivity < ApplicationRecord
    self.table_name = Escalated.table_name("ticket_activities")

    belongs_to :ticket, class_name: "Escalated::Ticket"
    belongs_to :causer, polymorphic: true, optional: true

    validates :action, presence: true

    scope :chronological, -> { order(created_at: :asc) }
    scope :reverse_chronological, -> { order(created_at: :desc) }
    scope :by_action, ->(action) { where(action: action) }
    scope :by_causer, ->(causer) { where(causer: causer) }
    scope :recent, ->(limit = 20) { reverse_chronological.limit(limit) }

    # Known actions:
    # ticket_created, ticket_updated, status_changed, ticket_assigned,
    # ticket_unassigned, reply_added, internal_note_added, tags_added,
    # tags_removed, department_changed, priority_changed, sla_breached,
    # ticket_escalated, ticket_merged

    def description
      case action
      when "ticket_created"
        "Ticket created"
      when "ticket_updated"
        changes = details&.keys&.reject { |k| k == "note" }&.join(", ")
        "Ticket updated: #{changes}"
      when "status_changed"
        "Status changed from #{details['from']} to #{details['to']}"
      when "ticket_assigned"
        "Ticket assigned"
      when "ticket_unassigned"
        "Ticket unassigned"
      when "reply_added"
        "Reply added"
      when "internal_note_added"
        "Internal note added"
      when "tags_added"
        "Tags added: #{Array(details['tag_names']).join(', ')}"
      when "tags_removed"
        "Tags removed: #{Array(details['tag_names']).join(', ')}"
      when "department_changed"
        "Department changed"
      when "priority_changed"
        "Priority changed from #{details['from']} to #{details['to']}"
      when "sla_breached"
        "SLA breached: #{details['breach_type']}"
      when "ticket_escalated"
        "Ticket escalated"
      else
        action.humanize
      end
    end

    def system_activity?
      causer.nil?
    end
  end
end
