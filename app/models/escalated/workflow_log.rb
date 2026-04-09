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
  end
end
