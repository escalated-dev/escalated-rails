module Escalated
  class TwoFactor < ApplicationRecord
    self.table_name = Escalated.table_name("two_factors")

    belongs_to :user, class_name: Escalated.configuration.user_class

    validates :user_id, uniqueness: true

    def confirmed?
      confirmed_at.present?
    end
  end
end
