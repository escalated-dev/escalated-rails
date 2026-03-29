module Escalated
  class Automation < ApplicationRecord
    self.table_name = Escalated.table_name("automations")

    serialize :conditions, coder: JSON
    serialize :actions, coder: JSON

    validates :name, presence: true
    validates :conditions, presence: true
    validates :actions, presence: true
    validate :conditions_must_be_array
    validate :actions_must_be_array

    scope :active, -> { where(active: true).order(position: :asc) }
    scope :ordered, -> { order(position: :asc, name: :asc) }

    def to_s
      name
    end

    private

    def conditions_must_be_array
      errors.add(:conditions, "must be an array") unless conditions.is_a?(Array)
    end

    def actions_must_be_array
      errors.add(:actions, "must be an array") unless actions.is_a?(Array)
    end
  end
end
