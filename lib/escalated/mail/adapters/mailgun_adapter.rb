require "openssl"

module Escalated
  module Mail
    module Adapters
      class MailgunAdapter < BaseAdapter
        # Parse a Mailgun inbound webhook into an InboundMessage.
        #
        # Mailgun POSTs multipart form data with fields:
        #   sender, from, recipient, subject, body-plain, body-html,
        #   Message-Id, In-Reply-To, References, message-headers, etc.
        #
        # @param request [ActionDispatch::Request]
        # @return [Escalated::Mail::InboundMessage]
        def parse_request(request)
          params = request.params

          from_name, from_email = parse_from(params)

          InboundMessage.new(
            from_email: from_email,
            from_name: from_name,
            to_email: safe_param(params, "recipient"),
            subject: safe_param(params, "subject", "(no subject)"),
            body_text: safe_param(params, "body-plain"),
            body_html: safe_param(params, "body-html"),
            message_id: safe_param(params, "Message-Id"),
            in_reply_to: safe_param(params, "In-Reply-To"),
            references: parse_references(safe_param(params, "References")),
            headers: parse_headers(safe_param(params, "message-headers")),
            attachments: []
          )
        end

        # Verify the Mailgun webhook signature.
        #
        # Mailgun sends: timestamp, token, signature
        # Signature = HMAC-SHA256(timestamp + token, signing_key)
        #
        # @param request [ActionDispatch::Request]
        # @return [Boolean]
        def verify_request(request)
          signing_key = Escalated.configuration.mailgun_signing_key
          if signing_key.blank?
            Rails.logger.warn("[Escalated::MailgunAdapter] Mailgun signing key not configured — rejecting webhook.")
            return false
          end

          params = request.params
          timestamp = params["timestamp"].to_s
          token = params["token"].to_s
          signature = params["signature"].to_s

          return false if timestamp.blank? || token.blank? || signature.blank?

          # Reject timestamps older than 5 minutes
          if (Time.current.to_i - timestamp.to_i).abs > 300
            Rails.logger.warn("[Escalated::MailgunAdapter] Webhook timestamp too old: #{timestamp}")
            return false
          end

          expected = OpenSSL::HMAC.hexdigest("SHA256", signing_key, "#{timestamp}#{token}")
          ActiveSupport::SecurityUtils.secure_compare(expected, signature)
        end

        private

        def parse_from(params)
          from_field = safe_param(params, "from")
          if from_field
            parse_email_address(from_field)
          else
            [nil, safe_param(params, "sender")]
          end
        end

        def parse_headers(headers_json)
          return {} if headers_json.blank?

          parsed = begin
            JSON.parse(headers_json)
          rescue JSON::ParserError
            []
          end

          # Mailgun sends headers as [[key, value], [key, value], ...]
          if parsed.is_a?(Array)
            parsed.each_with_object({}) { |pair, hash| hash[pair[0]] = pair[1] if pair.is_a?(Array) && pair.size >= 2 }
          else
            {}
          end
        end
      end
    end
  end
end
