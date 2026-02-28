module Escalated
  module Services
    class SkillRoutingService
      def find_matching_agents(ticket)
        tag_names = ticket.tags.pluck(:name)
        return Escalated.configuration.user_class.constantize.none if tag_names.empty?

        skill_ids = Escalated::Skill.where(name: tag_names).pluck(:id)
        return Escalated.configuration.user_class.constantize.none if skill_ids.empty?

        agent_user_ids = Escalated::AgentSkill.where(skill_id: skill_ids).distinct.pluck(:user_id)
        return Escalated.configuration.user_class.constantize.none if agent_user_ids.empty?

        user_class = Escalated.configuration.user_class.constantize
        user_class.where(id: agent_user_ids)
          .left_joins(:escalated_assigned_tickets)
          .where.not(Escalated.table_name("tickets") => { status: [:resolved, :closed] })
          .or(user_class.where(id: agent_user_ids).left_joins(:escalated_assigned_tickets).where(Escalated.table_name("tickets") => { id: nil }))
          .group(:id)
          .order(Arel.sql("COUNT(#{Escalated.table_name("tickets")}.id) ASC"))
      end
    end
  end
end
