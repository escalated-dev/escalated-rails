# frozen_string_literal: true

module Escalated
  class SkillRoutingDepartment < ApplicationRecord
    self.table_name = Escalated.table_name('skill_routing_departments')

    belongs_to :skill, class_name: 'Escalated::Skill'
    belongs_to :department, class_name: 'Escalated::Department'

    validates :department_id, uniqueness: { scope: :skill_id }
  end
end
