# frozen_string_literal: true

module Escalated
  class DelayedAction < ApplicationRecord
    self.table_name = Escalated.table_name('delayed_actions')

    belongs_to :workflow
    belongs_to :ticket

    serialize :action_data, coder: JSON

    validates :action_data, presence: true
    validates :execute_at, presence: true

    scope :pending, -> { where(executed: false).where(execute_at: ..Time.current) }
    scope :upcoming, -> { where(executed: false).where('execute_at > ?', Time.current) }
  end
end
