# frozen_string_literal: true

module Escalated
  module Support
    # The placeholder an admin settings page shows for a stored secret.
    #
    # The page learns only that a secret is set. Posting the placeholder back
    # means "keep the stored value"; anything else replaces it.
    module SecretMask
      MASK = '********'

      # Also matches the older "abc*****" form, so a settings tab opened before
      # an upgrade does not overwrite the secret with its placeholder.
      PATTERN = /\A.{0,3}\*{3,}\z/

      module_function

      def mask(value)
        value.nil? || value.to_s.empty? ? '' : MASK
      end

      def masked?(value)
        value.is_a?(String) && !value.empty? && PATTERN.match?(value)
      end
    end
  end
end
