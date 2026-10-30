# frozen_string_literal: true

require 'rotp'

module Escalated
  module Services
    # TOTP (RFC 6238: SHA-1, 6 digits, 30 s steps) through the rotp gem, with
    # one step of drift either side, plus single-use recovery codes (ADR
    # 2026-10-29-configurable-access-features).
    class TwoFactorService
      PERIOD = 30
      DIGITS = 6
      DRIFT = PERIOD

      # A random 32-character base32 secret (160 bits, the RFC 4226 recommendation).
      def generate_secret
        ROTP::Base32.random(20)
      end

      # The otpauth:// URI an authenticator app reads, with the parameters
      # spelled out (some apps ignore defaults they are not given).
      def generate_qr_uri(secret, email)
        issuer = self.class.issuer
        query = "secret=#{secret}&issuer=#{issuer}&algorithm=SHA1&digits=#{DIGITS}&period=#{PERIOD}"
        "otpauth://totp/#{issuer}:#{email}?#{query}"
      end

      # Whether the code is valid for the secret right now (no replay check).
      def verify(secret, code)
        !totp(secret).verify(normalize(code), drift_behind: DRIFT, drift_ahead: DRIFT).nil?
      end

      # Checks a code for an enrolment and records its time step, refusing a
      # step at or before the last one accepted, so a code works once.
      def verify_and_consume(two_factor, code)
        code = normalize(code)
        return false unless code.match?(/\A\d{6}\z/)

        last = two_factor.last_used_step
        after = last.nil? ? nil : (last.to_i * PERIOD) + 1
        at = totp(two_factor.secret).verify(code, drift_behind: DRIFT, drift_ahead: DRIFT, after: after)
        return false if at.nil?

        step = at.to_i / PERIOD
        table = Escalated::TwoFactor
        updated = table.where(id: two_factor.id)
                       .where('last_used_step IS NULL OR last_used_step < ?', step)
                       .update_all(last_used_step: step)
        return false unless updated == 1

        two_factor.last_used_step = step
        true
      end

      # Uses a recovery code: true, and it is removed, when it matches one.
      def use_recovery_code(two_factor, code)
        given = code.to_s.strip.upcase
        return false if given.empty?

        codes = two_factor.recovery_codes
        index = codes.index { |candidate| ActiveSupport::SecurityUtils.secure_compare(candidate.to_s.upcase, given) }
        return false if index.nil?

        codes.delete_at(index)
        two_factor.update!(recovery_codes: codes)
        true
      end

      def generate_recovery_codes
        Array.new(8) { "#{SecureRandom.hex(4).upcase}-#{SecureRandom.hex(4).upcase}" }
      end

      def self.issuer
        configured = (Escalated.configuration.two_factor || {}).to_h.symbolize_keys[:issuer]
        configured.presence || ENV['ESCALATED_TWO_FACTOR_ISSUER'].presence || begin
          Rails.application.class.module_parent_name
        rescue StandardError
          'Escalated'
        end
      end

      # Whether staff must enrol: the two_factor_required setting once saved,
      # else config.two_factor[:required] / ESCALATED_TWO_FACTOR_REQUIRED. Only
      # while the two-factor switch is on.
      def self.required?
        return false unless Escalated::Support::AccessFeatures.two_factor?

        configured = (Escalated.configuration.two_factor || {}).to_h.symbolize_keys[:required]
        configured = ENV.fetch('ESCALATED_TWO_FACTOR_REQUIRED', nil) if configured.nil?
        fallback = configured == true || %w[1 true yes on].include?(configured.to_s.downcase)
        stored = Escalated::EscalatedSetting.get('two_factor_required')
        stored.nil? || stored == '' ? fallback : %w[1 true on].include?(stored.to_s)
      end

      def self.confirmed_for(user)
        return nil if user.nil?

        Escalated::TwoFactor.confirmed.find_by(user_id: user.id)
      end

      private

      def totp(secret)
        ROTP::TOTP.new(secret, digits: DIGITS, interval: PERIOD)
      end

      def normalize(code)
        code.to_s.gsub(/\s+/, '')
      end
    end
  end
end
