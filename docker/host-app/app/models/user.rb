class User < ApplicationRecord
  alias_attribute :is_admin?, :is_admin
  alias_attribute :is_agent?, :is_agent

  def escalated_admin?
    is_admin
  end

  def escalated_agent?
    is_agent || is_admin
  end
end
