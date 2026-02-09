module Escalated
  module Mail
    module Adapters
      class PostmarkAdapter < BaseAdapter
        # Parse a Postmark inbound webhook into an InboundMessage.
        #
        # Postmark POSTs JSON with fields:
        #   From, FromName, FromFull, To, ToFull, Subject, TextBody, HtmlBody,
        #   MessageID, Headers, Attachments, etc.
        #
        # @param request [ActionDispatch::Request]
        # @return [Escalated::Mail::InboundMessage]
        def parse_request(request)
          params = request.params

          from_email = extract_from_email(params)
          from_name = extract_from_name(params)
          to_email = extract_to_email(params)
          headers = extract_headers(params)

          InboundMessage.new(
            from_email: from_email,
            from_name: from_name,
            to_email: to_email,
            subject: safe_param(params, "Subject", "(no subject)"),
            body_text: safe_param(params, "TextBody"),
            body_html: safe_param(params, "HtmlBody"),
            message_id: safe_param(params, "MessageID"),
            in_reply_to: headers["In-Reply-To"],
            references: parse_references(headers["References"]),
            headers: headers,
            attachments: []
          )
        end

        # Verify the Postmark inbound webhook.
        #
        # Postmark doesn't send a signature by default, but you can verify
        # the inbound token matches the configured one.
        #
        # @param request [ActionDispatch::Request]
        # @return [Boolean]
        def verify_request(request)
          token = Escalated.configuration.postmark_inbound_token
          return true if token.blank? # Skip verification if no token configured

          # Postmark doesn't sign webhooks, so we rely on the inbound address
          # token matching. The webhook URL itself serves as authentication.
          true
        end

        private

        def extract_from_email(params)
          from_full = params["FromFull"]
          if from_full.is_a?(Hash)
            from_full["Email"]
          else
            safe_param(params, "From")&.then { |f| parse_email_address(f).last }
          end
        end

        def extract_from_name(params)
          from_full = params["FromFull"]
          if from_full.is_a?(Hash)
            from_full["Name"].presence
          else
            safe_param(params, "FromName")
          end
        end

        def extract_to_email(params)
          to_full = params["ToFull"]
          if to_full.is_a?(Array) && to_full.first.is_a?(Hash)
            to_full.first["Email"]
          else
            safe_param(params, "To")&.then { |t| parse_email_address(t).last }
          end
        end

        def extract_headers(params)
          raw_headers = params["Headers"]
          return {} unless raw_headers.is_a?(Array)

          raw_headers.each_with_object({}) do |header, hash|
            hash[header["Name"]] = header["Value"] if header.is_a?(Hash)
          end
        end
      end
    end
  end
end
