# frozen_string_literal: true

module Escalated
  class AgentSkill < ApplicationRecord
    self.table_name = Escalated.table_name('agent_skills')
    self.primary_key = %i[user_id skill_id]

    attribute :proficiency, :integer, default: 3

    belongs_to :user, class_name: Escalated.configuration.user_class
    belongs_to :skill, class_name: 'Escalated::Skill'

    validates :user_id, uniqueness: { scope: :skill_id }
    validates :proficiency, inclusion: { in: 1..5 }
  end
end
