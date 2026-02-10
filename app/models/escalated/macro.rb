module Escalated
  class Macro < ApplicationRecord
    self.table_name = Escalated.table_name("macros")

    belongs_to :creator,
               class_name: Escalated.configuration.user_class,
               foreign_key: :created_by,
               optional: true

    validates :name, presence: true
    validates :actions, presence: true

    scope :shared, -> { where(is_shared: true) }
    scope :personal, -> { where(is_shared: false) }
    scope :for_agent, ->(user_id) { where(is_shared: true).or(where(created_by: user_id)) }
    scope :ordered, -> { order(:order, :name) }
  end
end
