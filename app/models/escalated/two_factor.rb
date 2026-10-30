# frozen_string_literal: true

module Escalated
  class TwoFactor < ApplicationRecord
    include Escalated::HidesSecrets

    self.table_name = Escalated.table_name('two_factors')

    # Never serialized: the TOTP seed and the recovery codes. Both are sealed
    # at rest (Escalated::Support::SealedValue).
    hides_secrets :secret, :recovery_codes

    belongs_to :user, class_name: Escalated.configuration.user_class

    validates :user_id, uniqueness: true

    scope :confirmed, -> { where.not(confirmed_at: nil) }

    def confirmed?
      confirmed_at.present?
    end

    def secret
      Escalated::Support::SealedValue.open(self[:secret])
    end

    def secret=(value)
      self[:secret] = Escalated::Support::SealedValue.seal(value)
    end

    # Enrolments made before sealing kept a plain JSON list; it is read as is.
    def recovery_codes
      raw = self[:recovery_codes]
      return Array(raw) unless Escalated::Support::SealedValue.sealed?(raw)

      Array(JSON.parse(Escalated::Support::SealedValue.open(raw)))
    end

    def recovery_codes=(codes)
      self[:recovery_codes] = Escalated::Support::SealedValue.seal(JSON.generate(Array(codes).map(&:to_s)))
    end
  end
end
