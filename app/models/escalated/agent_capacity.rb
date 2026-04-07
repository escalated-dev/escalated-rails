# frozen_string_literal: true

module Escalated
  class AgentCapacity < ApplicationRecord
    self.table_name = Escalated.table_name('agent_capacity')

    belongs_to :user, class_name: Escalated.configuration.user_class

    validates :user_id, uniqueness: { scope: :channel }

    def load_percentage
      return 0 if max_concurrent.to_i.zero?

      ((current_count.to_f / max_concurrent) * 100).round
    end

    def has_capacity?
      current_count < max_concurrent
    end
  end
end
