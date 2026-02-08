module Escalated
  class SlaPolicy < ApplicationRecord
    self.table_name = Escalated.table_name("sla_policies")

    has_many :tickets, class_name: "Escalated::Ticket", dependent: :nullify
    has_many :departments,
             class_name: "Escalated::Department",
             foreign_key: :default_sla_policy_id,
             dependent: :nullify

    validates :name, presence: true, uniqueness: { case_sensitive: false }
    validates :first_response_hours, presence: true
    validates :resolution_hours, presence: true

    scope :active, -> { where(is_active: true) }
    scope :default_policy, -> { where(is_default: true) }
    scope :ordered, -> { order(:name) }

    # first_response_hours and resolution_hours are JSON columns
    # stored as: { "low": 24, "medium": 8, "high": 4, "urgent": 2, "critical": 1 }

    def first_response_hours_for(priority)
      return nil unless first_response_hours.is_a?(Hash)

      hours = first_response_hours[priority.to_s]
      hours&.to_f
    end

    def resolution_hours_for(priority)
      return nil unless resolution_hours.is_a?(Hash)

      hours = resolution_hours[priority.to_s]
      hours&.to_f
    end

    def active?
      is_active
    end

    def default?
      is_default
    end

    def priority_targets
      Escalated::Ticket.priorities.keys.map do |priority|
        {
          priority: priority,
          first_response: first_response_hours_for(priority),
          resolution: resolution_hours_for(priority)
        }
      end
    end
  end
end
