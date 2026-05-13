# frozen_string_literal: true

module Escalated
  class Automation < ApplicationRecord
    self.table_name = Escalated.table_name('automations')

    validates :name, presence: true
    validate :conditions_must_be_present
    validate :actions_must_be_present
    validate :conditions_must_be_array
    validate :actions_must_be_array

    scope :active, -> { where(active: true).order(position: :asc) }
    scope :ordered, -> { order(position: :asc, name: :asc) }

    def to_s
      name
    end

    private

    def conditions_must_be_present
      errors.add(:conditions, :blank) if conditions.nil?
    end

    def actions_must_be_present
      errors.add(:actions, :blank) if actions.nil?
    end

    def conditions_must_be_array
      errors.add(:conditions, 'must be an array') unless conditions.is_a?(Array)
    end

    def actions_must_be_array
      errors.add(:actions, 'must be an array') unless actions.is_a?(Array)
    end
  end
end
