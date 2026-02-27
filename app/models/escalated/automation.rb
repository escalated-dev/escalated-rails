module Escalated
  class Automation < ApplicationRecord
    self.table_name = Escalated.table_name("automations")

    validates :name, presence: true

    scope :active, -> { where(active: true).order(position: :asc) }

    def to_s
      name
    end
  end
end
