# frozen_string_literal: true

module Escalated
  class CustomObjectRecord < ApplicationRecord
    self.table_name = Escalated.table_name('custom_object_records')

    belongs_to :object, class_name: 'Escalated::CustomObject'
  end
end
