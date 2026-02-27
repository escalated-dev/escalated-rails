module Escalated
  class CustomObject < ApplicationRecord
    self.table_name = Escalated.table_name("custom_objects")

    has_many :records,
             class_name: "Escalated::CustomObjectRecord",
             foreign_key: :object_id,
             dependent: :destroy

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true

    def to_s
      name
    end
  end
end
