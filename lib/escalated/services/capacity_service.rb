# frozen_string_literal: true

module Escalated
  module Services
    class CapacityService
      def can_accept_ticket?(user_id, channel: 'default')
        capacity = Escalated::AgentCapacity.find_or_create_by(user_id: user_id, channel: channel) do |c|
          c.max_concurrent = 10
          c.current_count = 0
        end

        capacity.has_capacity?
      end

      def increment_load(user_id, channel: 'default')
        capacity = Escalated::AgentCapacity.find_or_create_by(user_id: user_id, channel: channel) do |c|
          c.max_concurrent = 10
          c.current_count = 0
        end

        capacity.increment!(:current_count)
      end

      def decrement_load(user_id, channel: 'default')
        capacity = Escalated::AgentCapacity.find_or_create_by(user_id: user_id, channel: channel) do |c|
          c.max_concurrent = 10
          c.current_count = 0
        end

        capacity.decrement!(:current_count) if capacity.current_count.positive?
      end

      def all_capacities
        Escalated::AgentCapacity.includes(:user).all
      end
    end
  end
end
