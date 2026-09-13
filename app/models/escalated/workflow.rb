# frozen_string_literal: true

module Escalated
  class Workflow < ApplicationRecord
    self.table_name = Escalated.table_name('workflows')

    # The triggers a workflow can be given: the NotificationService events that
    # WorkflowSubscriber maps and that something actually dispatches. The admin
    # form offers exactly this list, so a workflow cannot be saved against an
    # event that never fires. (The subscriber also maps sla_warning, which
    # nothing dispatches.)
    TRIGGER_EVENTS = %w[
      ticket.created ticket.status_changed ticket.assigned ticket.priority_changed
      ticket.replied ticket.escalated sla.breached
    ].freeze

    has_many :workflow_logs, dependent: :destroy
    has_many :delayed_actions, dependent: :destroy

    before_validation :default_conditions

    validates :name, presence: true
    validates :trigger_event, presence: true, inclusion: { in: TRIGGER_EVENTS }
    validate :conditions_must_be_valid
    validate :actions_must_be_present

    scope :active, -> { where(is_active: true).order(position: :asc) }
    scope :for_event, ->(event) { active.where(trigger_event: event) }
    scope :ordered, -> { order(position: :asc, name: :asc) }

    # Alias for frontend compatibility: the frontend uses `trigger` instead of `trigger_event`
    def trigger
      trigger_event
    end

    private

    # Omitted conditions match every ticket.
    def default_conditions
      self.conditions = { 'all' => [] } if conditions.nil?
    end

    # Exactly one of all/any holding a list. A flat list, stored before the
    # admin contract, is still read as all.
    def conditions_must_be_valid
      return if conditions.is_a?(Array)
      return if conditions.is_a?(Hash) && conditions.size == 1 &&
                %w[all any].include?(conditions.keys.first.to_s) && conditions.values.first.is_a?(Array)

      errors.add(:conditions, 'must be an object with exactly one of all or any, holding a list')
    end

    def actions_must_be_present
      if actions.blank?
        errors.add(:actions, :blank)
      elsif !actions.is_a?(Array)
        errors.add(:actions, 'must be an array')
      end
    end
  end
end
