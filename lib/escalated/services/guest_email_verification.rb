# frozen_string_literal: true

require 'openssl'
require 'securerandom'

module Escalated
  module Services
    # Proof that a guest controls a mailbox (escalated-laravel
    # docs/guest-access.md): an eight-digit code, emailed and nowhere else,
    # that expires after ten minutes, allows five guesses and is used once.
    #
    # Code delivery is budgeted per mailbox and client IP, so one client
    # cannot use up the owner's budget, and per mailbox across all clients,
    # so the mailbox cannot be flooded.
    class GuestEmailVerification
      CODE_TTL = 10.minutes
      MAX_ATTEMPTS = 5

      class InvalidRequest < StandardError; end
      class InvalidCode < StandardError; end

      class TooManyRequests < StandardError
        attr_reader :retry_after

        def initialize(retry_after)
          @retry_after = retry_after
          super('Please wait before requesting another code.')
        end
      end

      EMAIL = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

      class << self
        def normalize(email)
          email.to_s.strip.downcase
        end

        # Emails a code and returns the verification id.
        def challenge(email, purpose, client_ip:)
          email = normalize(email)
          purpose = purpose.to_s
          raise InvalidRequest, 'Enter a valid email address.' unless email.length <= 255 && email.match?(EMAIL)
          unless Escalated::GuestVerification::PURPOSES.include?(purpose)
            raise InvalidRequest, 'Choose ticket, chat or lookup.'
          end

          spend_budget(email, client_ip)
          Escalated::GuestVerification.expired.where(created_at: ...1.day.ago).delete_all

          id = SecureRandom.uuid
          code = format('%08d', SecureRandom.random_number(100_000_000))
          verification = Escalated::GuestVerification.create!(
            id: id, email_digest: digest("email:#{email}"), purpose: purpose,
            code_hash: digest("code:#{id}:#{code}"), expires_at: CODE_TTL.from_now
          )
          begin
            Escalated::GuestMailer.verification_code(email, code).deliver_now
          rescue StandardError
            verification.delete
            raise
          end
          id
        end

        # Runs the block when the code is right, consuming it in the same
        # transaction. A wrong guess still counts; a block that raises rolls
        # the consumption back so the guest can retry.
        def consume(id, code, email, purpose)
          result = Escalated::GuestVerification.transaction do
            verification = Escalated::GuestVerification.lock.find_by(id: id.to_s)
            next { valid: false } unless usable?(verification)

            verification.update_columns(attempts: verification.attempts + 1)
            next { valid: false } unless matches?(verification, code, email, purpose)

            verification.update_columns(used_at: Time.current)
            { valid: true, value: yield }
          end
          raise InvalidCode, 'This code is invalid, expired or already used. Request a new code.' unless result[:valid]

          result[:value]
        end

        private

        def usable?(verification)
          verification && verification.used_at.nil? && verification.expires_at > Time.current &&
            verification.attempts < MAX_ATTEMPTS
        end

        def matches?(verification, code, email, purpose)
          ActiveSupport::SecurityUtils.secure_compare(verification.code_hash,
                                                      digest("code:#{verification.id}:#{code}")) &&
            ActiveSupport::SecurityUtils.secure_compare(verification.email_digest,
                                                        digest("email:#{normalize(email)}")) &&
            verification.purpose == purpose.to_s
        end

        def spend_budget(email, client_ip)
          mailbox = "escalated:guest-email:#{digest("email:#{email}")}"
          client = "#{mailbox}:client:#{digest("ip:#{client_ip}")}"
          per_client = [Escalated.configuration.guest_codes_per_client_per_hour.to_i, 1].max
          per_mailbox = [Escalated.configuration.guest_codes_per_mailbox_per_hour.to_i, per_client].max

          { client => per_client, mailbox => per_mailbox }.each do |key, limit|
            count = Rails.cache.read(key).to_i
            raise TooManyRequests, retry_after(key) if count >= limit
          end
          [client, mailbox].each { |key| hit(key) }
        end

        # Rails.cache.increment is atomic on the shared stores (Redis,
        # Memcached); the expiry is set by the first write in the hour.
        def hit(key)
          Rails.cache.write("#{key}:reset", 1.hour.from_now.to_i, expires_in: 1.hour, unless_exist: true)
          return if Rails.cache.increment(key, 1, expires_in: 1.hour)

          Rails.cache.write(key, 1, expires_in: 1.hour)
        end

        def retry_after(key)
          reset = Rails.cache.read("#{key}:reset").to_i
          [reset - Time.current.to_i, 1].max
        end

        def digest(value)
          OpenSSL::HMAC.hexdigest('SHA256', secret, "escalated-guest-email:#{value}")
        end

        def secret
          @secret ||= Rails.application.key_generator.generate_key('escalated guest email verification', 32)
        end
      end
    end
  end
end
