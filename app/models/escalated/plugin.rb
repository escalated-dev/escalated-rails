module Escalated
  class Plugin < ApplicationRecord
    self.table_name = Escalated.table_name("plugins")

    validates :slug, presence: true, uniqueness: true,
              format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, message: "must be a lowercase slug (e.g. my-plugin)" }

    scope :active,   -> { where(is_active: true) }
    scope :inactive, -> { where(is_active: false) }
    scope :ordered,  -> { order(:slug) }

    def active?
      is_active
    end
  end
end
