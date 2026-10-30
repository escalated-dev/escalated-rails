# frozen_string_literal: true

require 'active_support/message_encryptor'

module Escalated
  module Support
    # Seals short secrets at rest (two-factor seeds and recovery codes) with
    # ActiveSupport::MessageEncryptor (AES-256-GCM), keyed from the host's
    # secret_key_base. A value stored before sealing existed is read as is and
    # sealed again when it is next written.
    module SealedValue
      PREFIX = 'sealed:v1:'

      module_function

      def seal(value)
        return nil if value.nil?

        PREFIX + encryptor.encrypt_and_sign(value.to_s)
      end

      def open(value)
        return value unless value.is_a?(String) && value.start_with?(PREFIX)

        encryptor.decrypt_and_verify(value.delete_prefix(PREFIX))
      end

      def sealed?(value)
        value.is_a?(String) && value.start_with?(PREFIX)
      end

      def encryptor
        @encryptor ||= begin
          key = Rails.application.key_generator.generate_key('escalated sealed value', 32)
          ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm')
        end
      end
    end
  end
end
