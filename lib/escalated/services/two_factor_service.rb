require "openssl"

module Escalated
  module Services
    class TwoFactorService
      PERIOD = 30
      DIGITS = 6

      def generate_secret
        chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        (0...16).map { chars[SecureRandom.random_number(32)] }.join
      end

      def generate_qr_uri(secret, email)
        issuer = Rails.application.class.module_parent_name rescue "Escalated"
        "otpauth://totp/#{issuer}:#{email}?secret=#{secret}&issuer=#{issuer}&algorithm=SHA1&digits=#{DIGITS}&period=#{PERIOD}"
      end

      def verify(secret, code)
        current_time = Time.now.to_i
        (-1..1).any? { |offset| generate_totp(secret, (current_time / PERIOD) + offset) == code }
      end

      def generate_recovery_codes
        8.times.map { "#{SecureRandom.hex(4).upcase}-#{SecureRandom.hex(4).upcase}" }
      end

      private

      def generate_totp(secret, time_step)
        key = base32_decode(secret)
        msg = [time_step].pack("Q>")
        hmac = OpenSSL::HMAC.digest("SHA1", key, msg)
        offset = hmac[-1].ord & 0x0F
        code = (hmac[offset].ord & 0x7F) << 24 |
               (hmac[offset + 1].ord & 0xFF) << 16 |
               (hmac[offset + 2].ord & 0xFF) << 8 |
               (hmac[offset + 3].ord & 0xFF)
        (code % (10**DIGITS)).to_s.rjust(DIGITS, "0")
      end

      def base32_decode(input)
        alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        bits = input.upcase.chars.map { |c| alphabet.index(c).to_s(2).rjust(5, "0") }.join
        bits.scan(/.{8}/).map { |b| b.to_i(2).chr }.join
      end
    end
  end
end
