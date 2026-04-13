# frozen_string_literal: true

module Escalated
  class WorkflowLog < ApplicationRecord
    self.table_name = Escalated.table_name('workflow_logs')

    belongs_to :workflow
    belongs_to :ticket

    serialize :actions_executed, coder: JSON

    validates :trigger_event, presence: true
    validates :status, presence: true, inclusion: { in: %w[success failure skipped] }

    scope :recent, -> { order(created_at: :desc) }
    scope :failures, -> { where(status: 'failure') }
    scope :successes, -> { where(status: 'success') }

    # --- Computed fields expected by the frontend ---

    # Alias: frontend reads `event` instead of `trigger_event`
    def event
      trigger_event
    end

    # Boolean alias: frontend reads `matched` for whether conditions were met
    def matched
      conditions_matched
    end

    # The raw actions array for the expanded detail view
    def action_details
      actions_executed
    end

    # Integer count of executed actions
    def actions_executed_count
      (actions_executed || []).size
    end

    # Milliseconds between started_at and completed_at
    def duration_ms
      return nil unless started_at && completed_at

      ((completed_at - started_at) * 1000).round
    end

    # Computed status: 'failed' when an error is present, otherwise 'success'
    def computed_status
      error_message.present? ? 'failed' : 'success'
    end

    # Eager-loaded relationship accessors
    def workflow_name
      workflow&.name
    end

    def ticket_reference
      ticket&.reference
    end
  end
end
