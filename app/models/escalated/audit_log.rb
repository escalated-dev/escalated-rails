# frozen_string_literal: true

module Escalated
  class AuditLog < ApplicationRecord
    self.table_name = Escalated.table_name('audit_logs')

    belongs_to :user, class_name: Escalated.configuration.user_class, optional: true
    belongs_to :auditable, polymorphic: true

    scope :recent, -> { order(created_at: :desc) }
    scope :by_action, ->(action) { where(action: action) }
    scope :by_user, ->(user_id) { where(user_id: user_id) }
  end
end
