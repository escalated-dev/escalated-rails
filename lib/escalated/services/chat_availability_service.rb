# frozen_string_literal: true

module Escalated
  module Services
    class ChatAvailabilityService
      class << self
        def available?(department_id: nil)
          agents = online_agents(department_id: department_id)
          agents.any?
        end

        def online_agents(department_id: nil)
          profiles = Escalated::AgentProfile.chat_online

          if department_id.present?
            department = Escalated::Department.find_by(id: department_id)
            if department
              agent_ids = department.agents.pluck(:id)
              profiles = profiles.where(user_id: agent_ids)
            end
          end

          profiles
        end

        def agent_chat_count(agent_id)
          Escalated::ChatSession.active.where(agent_id: agent_id).count
        end

        def agent_available?(agent_id, max_concurrent: nil)
          profile = Escalated::AgentProfile.find_by(user_id: agent_id)
          return false unless profile&.chat_online?

          max = max_concurrent || default_max_concurrent
          agent_chat_count(agent_id) < max
        end

        private

        def default_max_concurrent
          rule = Escalated::ChatRoutingRule.active.ordered.first
          rule&.max_concurrent_per_agent || 5
        end
      end
    end
  end
end
