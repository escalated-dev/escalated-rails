# frozen_string_literal: true

module Escalated
  class SavedView < ApplicationRecord
    self.table_name = Escalated.table_name('saved_views')

    belongs_to :user, class_name: Escalated.configuration.user_class, optional: true

    validates :name, presence: true, length: { maximum: 100 }

    scope :for_user, ->(user_id) { where(user_id: user_id) }
    scope :shared, -> { where(is_shared: true) }
    scope :default_views, -> { where(is_default: true) }
    scope :ordered, -> { order(position: :asc, name: :asc) }
    scope :accessible_by, ->(user_id) { where(user_id: user_id).or(where(is_shared: true)) }
  end
end
