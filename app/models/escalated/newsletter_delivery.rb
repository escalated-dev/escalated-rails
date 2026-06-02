# frozen_string_literal: true

module Escalated
  class NewsletterDelivery < ApplicationRecord
    self.table_name = Escalated.table_name('newsletter_deliveries')

    # Don't auto-touch updated_at — the migration intentionally omits it so
    # high-volume delivery rows skip a write on every tick.
    self.record_timestamps = false

    STATUSES = %w[pending queued sent bounced complained suppressed failed].freeze

    belongs_to :newsletter, class_name: 'Escalated::Newsletter'
    belongs_to :contact, class_name: 'Escalated::Contact'

    validates :tracking_token, presence: true, uniqueness: true
    validates :email_at_send, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }

    scope :pending, -> { where(status: 'pending') }
    scope :queued, -> { where(status: 'queued') }
    scope :terminal, -> { where(status: %w[sent bounced complained suppressed failed]) }
  end
end
