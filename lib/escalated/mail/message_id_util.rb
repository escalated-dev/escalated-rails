# frozen_string_literal: true

require 'openssl'

module Escalated
  module Mail
    # Pure helpers for RFC 5322 Message-ID threading and signed Reply-To
    # addresses. Mirrors the NestJS reference
    # `escalated-nestjs/src/services/email/message-id.ts` and the Spring
    # / WordPress / .NET / Phoenix / Laravel ports.
    #
    # ## Message-ID format
    #   <ticket-{ticket_id}@{domain}>             initial ticket email
    #   <ticket-{ticket_id}-reply-{reply_id}@{domain}>  agent reply
    #
    # ## Signed Reply-To format
    #   reply+{ticket_id}.{hmac8}@{domain}
    #
    # The signed Reply-To carries ticket identity even when clients strip
    # our Message-ID / In-Reply-To headers — the inbound provider webhook
    # verifies the 8-char HMAC-SHA256 prefix before routing a reply to
    # its ticket.
    module MessageIdUtil
      module_function

      # Build an RFC 5322 Message-ID. Pass `nil` for `reply_id` on the
      # initial ticket email; the `-reply-{id}` tail is appended only
      # when `reply_id` is non-nil.
      def build_message_id(ticket_id, reply_id, domain)
        body = reply_id.nil? ? "ticket-#{ticket_id}" : "ticket-#{ticket_id}-reply-#{reply_id}"
        "<#{body}@#{domain}>"
      end

      # Extract the ticket id from a Message-ID we issued. Accepts the
      # header value with or without angle brackets. Returns `nil` when
      # the input doesn't match our shape.
      def parse_ticket_id_from_message_id(raw)
        return nil if raw.blank?

        if (m = raw.match(/ticket-(\d+)(?:-reply-\d+)?@/i))
          Integer(m[1])
        end
      rescue ArgumentError
        nil
      end

      # Build a signed Reply-To address of the form
      # `reply+{ticket_id}.{hmac8}@{domain}`.
      def build_reply_to(ticket_id, secret, domain)
        "reply+#{ticket_id}.#{sign(ticket_id, secret)}@#{domain}"
      end

      # Verify a reply-to address (full `local@domain` or just the local
      # part). Returns the ticket id on match, `nil` otherwise. Uses
      # `secure_compare` for timing-safe verification.
      def verify_reply_to(address, secret)
        return nil if address.blank?

        local = address.include?('@') ? address.split('@', 2).first : address
        return nil unless (m = local.match(/\Areply\+(\d+)\.([a-f0-9]{8})\z/i))

        ticket_id = Integer(m[1])
        expected = sign(ticket_id, secret)
        secure_compare(expected.downcase, m[2].downcase) ? ticket_id : nil
      rescue ArgumentError
        nil
      end

      # 8-character HMAC-SHA256 prefix over the ticket id.
      def sign(ticket_id, secret)
        OpenSSL::HMAC.hexdigest('SHA256', secret, ticket_id.to_s)[0, 8]
      end

      # Timing-safe string comparison, equivalent to ActiveSupport's
      # ActiveSupport::SecurityUtils.secure_compare when available.
      def secure_compare(a, b)
        return false unless a.bytesize == b.bytesize

        l = a.unpack("C#{a.bytesize}")
        res = 0
        b.each_byte { |byte| res |= byte ^ l.shift }
        res.zero?
      end
    end
  end
end
