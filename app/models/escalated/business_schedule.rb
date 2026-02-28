module Escalated
  class BusinessSchedule < ApplicationRecord
    self.table_name = Escalated.table_name("business_schedules")

    has_many :holidays, class_name: "Escalated::Holiday", foreign_key: :schedule_id, dependent: :destroy

    def to_s
      name
    end
  end
end
