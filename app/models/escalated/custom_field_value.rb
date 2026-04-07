# frozen_string_literal: true

module Escalated
  class CustomFieldValue < ApplicationRecord
    self.table_name = Escalated.table_name('custom_field_values')

    belongs_to :custom_field, class_name: 'Escalated::CustomField'
    belongs_to :entity, polymorphic: true

    def to_s
      "#{custom_field.name}: #{value}"
    end
  end
end
