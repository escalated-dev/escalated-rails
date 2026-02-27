module Escalated
  class AgentProfile < ApplicationRecord
    self.table_name = Escalated.table_name("agent_profiles")

    belongs_to :user, class_name: Escalated.configuration.user_class

    validates :user_id, uniqueness: true

    def light_agent?
      agent_type == "light"
    end

    def full_agent?
      agent_type == "full"
    end

    def self.for_user(user_id)
      find_by(user_id: user_id)
    end
  end
end
