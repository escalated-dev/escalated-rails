# frozen_string_literal: true

module Escalated
  class Plugin < ApplicationRecord
    self.table_name = Escalated.table_name('plugins')

    validates :slug, presence: true, uniqueness: true,
                     format: {
                       # The plugin contract's slug: an SDK plugin named
                       # "@acme/plugin-crm" is "acme--plugin-crm".
                       with: /\A[A-Za-z0-9_-]+\z/,
                       message: 'must be a slug (letters, digits, "-" and "_")'
                     }

    scope :active,   -> { where(is_active: true) }
    scope :inactive, -> { where(is_active: false) }
    scope :ordered,  -> { order(:slug) }

    def active?
      is_active
    end
  end
end
