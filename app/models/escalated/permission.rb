# frozen_string_literal: true

module Escalated
  class Permission < ApplicationRecord
    self.table_name = Escalated.table_name('permissions')

    has_and_belongs_to_many :roles,
                            join_table: Escalated.table_name('role_permissions'),
                            class_name: 'Escalated::Role'

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true

    scope :ordered, -> { order(group: :asc, name: :asc) }

    def to_s
      name
    end
  end
end
