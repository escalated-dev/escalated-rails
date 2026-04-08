# frozen_string_literal: true

module Escalated
  class ChatRoutingRule < ApplicationRecord
    self.table_name = Escalated.table_name('chat_routing_rules')

    belongs_to :department, class_name: 'Escalated::Department', optional: true

    ROUTING_STRATEGIES = %w[round_robin least_busy random skills_based].freeze
    OFFLINE_BEHAVIORS = %w[show_form hide_widget show_message].freeze

    validates :routing_strategy, presence: true, inclusion: { in: ROUTING_STRATEGIES }
    validates :offline_behavior, presence: true, inclusion: { in: OFFLINE_BEHAVIORS }
    validates :max_queue_size, numericality: { greater_than: 0 }
    validates :max_concurrent_per_agent, numericality: { greater_than: 0 }
    validates :auto_close_after_minutes, numericality: { greater_than: 0 }

    scope :active, -> { where(is_active: true) }
    scope :ordered, -> { order(:position) }

    def active?
      is_active
    end
  end
end
