# frozen_string_literal: true

module Escalated
  class Mention < ApplicationRecord
    self.table_name = Escalated.table_name('mentions')

    belongs_to :reply
    belongs_to :user, class_name: Escalated.configuration.user_class

    validates :user_id, uniqueness: { scope: :reply_id }

    scope :unread, -> { where(read_at: nil) }
    scope :read, -> { where.not(read_at: nil) }
    scope :for_user, ->(user_id) { where(user_id: user_id) }
    scope :recent, -> { order(created_at: :desc) }

    def read?
      read_at.present?
    end

    def mark_as_read!
      update!(read_at: Time.current) unless read?
    end
  end
end
