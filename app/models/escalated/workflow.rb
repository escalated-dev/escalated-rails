# frozen_string_literal: true

module Escalated
  class Workflow < ApplicationRecord
    self.table_name = Escalated.table_name('workflows')

    serialize :conditions, coder: JSON
    serialize :actions, coder: JSON

    has_many :workflow_logs, dependent: :destroy
    has_many :delayed_actions, dependent: :destroy

    validates :name, presence: true
    validates :trigger_event, presence: true, inclusion: {
      in: %w[ticket.created ticket.updated ticket.status_changed ticket.assigned
             ticket.priority_changed ticket.tagged ticket.department_changed
             reply.created reply.agent_reply sla.warning sla.breached ticket.reopened]
    }
    validates :conditions, presence: true
    validates :actions, presence: true
    validate :conditions_must_be_valid
    validate :actions_must_be_array

    scope :active, -> { where(is_active: true).order(position: :asc) }
    scope :for_event, ->(event) { active.where(trigger_event: event) }
    scope :ordered, -> { order(position: :asc, name: :asc) }

    # Alias for frontend compatibility: the frontend uses `trigger` instead of `trigger_event`
    def trigger
      trigger_event
    end

    TRIGGER_EVENTS = %w[
      ticket.created ticket.updated ticket.status_changed ticket.assigned
      ticket.priority_changed ticket.tagged ticket.department_changed
      reply.created reply.agent_reply sla.warning sla.breached ticket.reopened
    ].freeze

    private

    def conditions_must_be_valid
      return if conditions.is_a?(Hash) && (conditions.key?('all') || conditions.key?('any'))
      return if conditions.is_a?(Array)

      errors.add(:conditions, 'must be an object with all/any keys or an array')
    end

    def actions_must_be_array
      errors.add(:actions, 'must be an array') unless actions.is_a?(Array)
    end
  end
end
