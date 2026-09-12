# frozen_string_literal: true

module Escalated
  class SavedView < ApplicationRecord
    self.table_name = Escalated.table_name('saved_views')

    # Carried here rather than as a column default: MySQL forbids a default on a
    # JSON column, so a database default made the engine impossible to install
    # there at all. Every adapter honours this one the same way.
    attribute :filters, default: -> { {} }

    belongs_to :user, class_name: Escalated.configuration.user_class, optional: true

    validates :name, presence: true, length: { maximum: 100 }

    scope :for_user, ->(user_id) { where(user_id: user_id) }
    scope :shared, -> { where(is_shared: true) }
    scope :default_views, -> { where(is_default: true) }
    scope :ordered, -> { order(position: :asc, name: :asc) }
    scope :accessible_by, ->(user_id) { where(user_id: user_id).or(where(is_shared: true)) }
  end
end
