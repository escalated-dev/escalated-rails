# frozen_string_literal: true

module Escalated
  class Holiday < ApplicationRecord
    self.table_name = Escalated.table_name('holidays')

    belongs_to :schedule, class_name: 'Escalated::BusinessSchedule'

    validates :name, presence: true
    validates :date, presence: true

    def to_s
      "#{name} (#{date})"
    end
  end
end
