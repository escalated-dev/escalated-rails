# frozen_string_literal: true

module Escalated
  class SkillRoutingTag < ApplicationRecord
    self.table_name = Escalated.table_name('skill_routing_tags')

    belongs_to :skill, class_name: 'Escalated::Skill'
    belongs_to :tag, class_name: 'Escalated::Tag'

    validates :tag_id, uniqueness: { scope: :skill_id }
  end
end
