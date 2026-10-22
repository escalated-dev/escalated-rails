# frozen_string_literal: true

module Escalated
  class TwoFactor < ApplicationRecord
    include Escalated::HidesSecrets

    self.table_name = Escalated.table_name('two_factors')

    # Never serialized: the TOTP seed and the recovery codes.
    hides_secrets :secret, :recovery_codes

    belongs_to :user, class_name: Escalated.configuration.user_class

    validates :user_id, uniqueness: true

    def confirmed?
      confirmed_at.present?
    end
  end
end
