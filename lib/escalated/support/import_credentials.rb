# frozen_string_literal: true

module Escalated
  module Support
    # Encrypts an import source's credentials (API tokens and the like) for
    # the two places they rest between requests: the wizard's session, from a
    # tested connection until the import starts, and the import job's
    # `credentials` column, until the run completes or is cancelled.
    #
    # The key is derived from the application's secret_key_base, so nothing
    # has to be configured: Active Record encryption, which this column used
    # before, raised on every save in an app without its keys.
    module ImportCredentials
      PURPOSE = 'escalated import credentials'

      module_function

      # @param credentials [Hash, nil]
      # @return [String, nil]
      def encrypt(credentials)
        return nil if credentials.nil?

        encryptor.encrypt_and_sign(credentials.to_h.stringify_keys, purpose: :escalated_import_credentials)
      end

      # @param value [String, nil]
      # @return [Hash, nil] nil when the value is absent, tampered with, or
      #   was written under another key.
      def decrypt(value)
        return nil if value.blank?

        decrypted = encryptor.decrypt_and_verify(value, purpose: :escalated_import_credentials)
        decrypted.is_a?(Hash) ? decrypted : nil
      rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature,
             JSON::ParserError, ArgumentError
        nil
      end

      # Coder for `serialize :credentials, coder: ImportCredentials`.
      def dump(credentials) = encrypt(credentials)
      def load(value) = decrypt(value)

      def encryptor
        key = Rails.application.key_generator.generate_key(PURPOSE, 32)
        ActiveSupport::MessageEncryptor.new(key, serializer: JSON)
      end
    end
  end
end
