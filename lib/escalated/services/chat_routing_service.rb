# frozen_string_literal: true

module Escalated
  module Services
    class ChatRoutingService
      class << self
        def find_available_agent(department_id: nil)
          rule = routing_rule_for(department_id)
          strategy = rule&.routing_strategy || 'round_robin'
          max_concurrent = rule&.max_concurrent_per_agent || 5

          candidates = available_agent_ids(department_id: department_id, max_concurrent: max_concurrent)
          return nil if candidates.empty?

          case strategy
          when 'round_robin'
            round_robin_select(candidates)
          when 'least_busy'
            least_busy_select(candidates)
          when 'random'
            candidates.sample
          else
            candidates.first
          end
        end

        def evaluate_routing(department_id: nil)
          rule = routing_rule_for(department_id)
          {
            available: ChatAvailabilityService.available?(department_id: department_id),
            queue_size: current_queue_size(department_id: department_id),
            max_queue_size: rule&.max_queue_size || 50,
            queue_full: queue_full?(department_id: department_id),
            offline_behavior: rule&.offline_behavior || 'show_form',
            queue_message: rule&.queue_message,
            offline_message: rule&.offline_message
          }
        end

        def get_queue_position(session)
          Escalated::ChatSession.waiting
                                .where(created_at: ..session.created_at)
                                .count
        end

        private

        def routing_rule_for(department_id)
          if department_id.present?
            Escalated::ChatRoutingRule.active.find_by(department_id: department_id) ||
              Escalated::ChatRoutingRule.active.where(department_id: nil).ordered.first
          else
            Escalated::ChatRoutingRule.active.ordered.first
          end
        end

        def available_agent_ids(department_id: nil, max_concurrent: 5)
          profiles = ChatAvailabilityService.online_agents(department_id: department_id)
          profiles.select { |p| ChatAvailabilityService.agent_chat_count(p.user_id) < max_concurrent }
                  .map(&:user_id)
        end

        def round_robin_select(agent_ids)
          last_assigned = Escalated::ChatSession
                          .where(agent_id: agent_ids)
                          .order(created_at: :desc)
                          .pick(:agent_id)

          if last_assigned
            idx = agent_ids.index(last_assigned)
            return agent_ids[(idx + 1) % agent_ids.size] if idx
          end

          agent_ids.first
        end

        def least_busy_select(agent_ids)
          counts = Escalated::ChatSession.active
                                         .where(agent_id: agent_ids)
                                         .group(:agent_id)
                                         .count
          agent_ids.min_by { |id| counts[id] || 0 }
        end

        def current_queue_size(department_id: nil)
          scope = Escalated::ChatSession.waiting
          if department_id.present?
            ticket_ids = Escalated::Ticket.chat.where(department_id: department_id).pluck(:id)
            scope = scope.where(ticket_id: ticket_ids)
          end
          scope.count
        end

        def queue_full?(department_id: nil)
          rule = routing_rule_for(department_id)
          max = rule&.max_queue_size || 50
          current_queue_size(department_id: department_id) >= max
        end
      end
    end
  end
end
