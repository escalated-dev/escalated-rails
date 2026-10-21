# frozen_string_literal: true

module Escalated
  # A one-time email code (Escalated::Services::GuestEmailVerification).
  class GuestVerification < ApplicationRecord
    self.table_name = Escalated.table_name('guest_verifications')
    self.primary_key = 'id'

    PURPOSES = %w[ticket chat lookup].freeze

    scope :expired, -> { where(expires_at: ...Time.current) }
  end
end
