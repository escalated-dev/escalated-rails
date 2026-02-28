module Escalated
  class Skill < ApplicationRecord
    self.table_name = Escalated.table_name("skills")

    has_many :agent_skills, class_name: "Escalated::AgentSkill", dependent: :destroy
    has_many :agents,
             through: :agent_skills,
             source: :user,
             class_name: Escalated.configuration.user_class

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true

    before_validation :generate_slug, if: -> { slug.blank? }

    def to_s
      name
    end

    private

    def generate_slug
      self.slug = name.to_s.parameterize(separator: "_")
    end
  end
end
