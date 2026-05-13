# frozen_string_literal: true

module Escalated
  module Services
    class SkillRoutingService
      def find_matching_agents(ticket)
        user_class = Escalated.configuration.user_class.constantize

        required_skill_ids = required_skill_ids_for(ticket)
        return user_class.none if required_skill_ids.empty?

        eligible_user_ids = eligible_agent_user_ids(required_skill_ids)
        return user_class.none if eligible_user_ids.empty?

        prof_sums = Escalated::AgentSkill
                    .where(user_id: eligible_user_ids, skill_id: required_skill_ids)
                    .group(:user_id)
                    .sum(:proficiency)

        open_loads = Escalated::Ticket
                     .where(assigned_to: eligible_user_ids)
                     .where.not(status: %i[resolved closed])
                     .group(:assigned_to)
                     .count

        ordered_ids = eligible_user_ids.sort_by do |uid|
          [-prof_sums.fetch(uid, 0), open_loads.fetch(uid, 0)]
        end

        user_class.where(id: ordered_ids).order(order_by_id_array(user_class.table_name, ordered_ids))
      end

      private

      def required_skill_ids_for(ticket)
        by_tags =
          if ticket.tag_ids.any?
            Escalated::Skill
              .joins(:routing_tags)
              .where(Escalated::SkillRoutingTag.table_name => { tag_id: ticket.tag_ids })
              .distinct
              .pluck(:id)
          else
            []
          end

        by_department =
          if ticket.department_id.present?
            Escalated::Skill
              .joins(:routing_departments)
              .where(Escalated::SkillRoutingDepartment.table_name => { department_id: ticket.department_id })
              .distinct
              .pluck(:id)
          else
            []
          end

        (by_tags + by_department).uniq
      end

      def eligible_agent_user_ids(required_skill_ids)
        needed = required_skill_ids.size
        Escalated::AgentSkill
          .where(skill_id: required_skill_ids)
          .group(:user_id)
          .having('COUNT(DISTINCT skill_id) = ?', needed)
          .pluck(:user_id)
      end

      def order_by_id_array(table_name, ordered_ids)
        return Arel.sql('1') if ordered_ids.empty?

        cases = ordered_ids.each_with_index.map { |id, idx| "WHEN #{id.to_i} THEN #{idx}" }.join(' ')
        Arel.sql("CASE #{table_name}.id #{cases} ELSE #{ordered_ids.length} END")
      end
    end
  end
end
