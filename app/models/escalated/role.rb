# frozen_string_literal: true

module Escalated
  class Role < ApplicationRecord
    self.table_name = Escalated.table_name('roles')

    has_and_belongs_to_many :permissions,
                            join_table: Escalated.table_name('role_permissions'),
                            class_name: 'Escalated::Permission'
    has_and_belongs_to_many :users,
                            join_table: Escalated.table_name('role_users'),
                            class_name: Escalated.configuration.user_class,
                            association_foreign_key: :user_id

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true

    before_validation :generate_slug, if: -> { slug.blank? }

    def has_permission?(slug)
      permissions.exists?(slug: slug)
    end

    def to_s
      name
    end

    private

    def generate_slug
      self.slug = name.to_s.parameterize(separator: '_')
    end
  end
end
