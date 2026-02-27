module Escalated
  class AgentSkill < ApplicationRecord
    self.table_name = Escalated.table_name("agent_skills")

    belongs_to :user, class_name: Escalated.configuration.user_class
    belongs_to :skill, class_name: "Escalated::Skill"

    validates :user_id, uniqueness: { scope: :skill_id }
  end
end
