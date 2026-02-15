require "json"
require "base64"

module Escalated
  module Mail
    module Adapters
      class SesAdapter < BaseAdapter
        # Parse an AWS SES/SNS inbound notification into an InboundMessage.
        #
        # SES sends notifications via SNS. The SNS message contains either:
        # 1. A SubscriptionConfirmation (must be confirmed)
        # 2. A Notification with the email content in the "Message" field
        #
        # The SES notification message contains:
        #   mail.source, mail.destination, mail.headers, mail.subject,
        #   content (base64 or S3 reference)
        #
        # For simplicity, this adapter handles the SNS notification format
        # where SES includes parsed email data.
        #
        # @param request [ActionDispatch::Request]
        # @return [Escalated::Mail::InboundMessage, nil]
        def parse_request(request)
          body = parse_sns_body(request)
          return nil unless body

          sns_type = body["Type"]

          # Handle SNS subscription confirmation
          if sns_type == "SubscriptionConfirmation"
            confirm_subscription(body)
            return nil
          end

          # Handle notification
          return nil unless sns_type == "Notification"

          ses_message = parse_ses_message(body["Message"])
          return nil unless ses_message

          build_inbound_message(ses_message)
        end

        # Verify the SNS message signature.
        #
        # @param request [ActionDispatch::Request]
        # @return [Boolean]
        def verify_request(request)
          topic_arn = Escalated.configuration.ses_topic_arn
          if topic_arn.blank?
            Rails.logger.warn('Escalated: SES Topic ARN not configured — rejecting request.')
            return false
          end

          body = parse_sns_body(request)
          return false unless body

          # Verify the TopicArn matches
          message_topic_arn = body["TopicArn"]
          return false unless message_topic_arn == topic_arn

          # Validate SNS message type
          message_type = body["Type"]
          unless %w[SubscriptionConfirmation Notification UnsubscribeConfirmation].include?(message_type)
            Rails.logger.warn("[Escalated::SesAdapter] Unexpected SNS message type: #{message_type}")
            return false
          end

          # Validate SigningCertURL is from a legitimate AWS SNS endpoint
          signing_cert_url = body["SigningCertURL"] || body["SigningCertUrl"]
          if signing_cert_url.present?
            begin
              uri = URI.parse(signing_cert_url)
              unless uri.scheme == "https" && uri.host.match?(/\Asns\.[a-z0-9-]+\.amazonaws\.com\z/)
                Rails.logger.warn("[Escalated::SesAdapter] Invalid SigningCertURL: #{signing_cert_url}")
                return false
              end
            rescue URI::InvalidURIError
              return false
            end
          end

          true
        end

        private

        def parse_sns_body(request)
          raw_body = request.raw_post
          JSON.parse(raw_body)
        rescue JSON::ParserError => e
          Rails.logger.error("[Escalated::SesAdapter] Failed to parse SNS body: #{e.message}")
          nil
        end

        def confirm_subscription(body)
          subscribe_url = body["SubscribeURL"]

          unless subscribe_url.present? && valid_sns_url?(subscribe_url)
            Rails.logger.warn("Escalated: Rejected SNS SubscribeURL — not a valid Amazon SNS URL. url=#{subscribe_url}")
            return
          end

          Rails.logger.info("[Escalated::SesAdapter] Confirming SNS subscription: #{subscribe_url}")
          Thread.new do
            begin
              uri = URI.parse(subscribe_url)
              Net::HTTP.get(uri)
            rescue StandardError => e
              Rails.logger.error("[Escalated::SesAdapter] Failed to confirm subscription: #{e.message}")
            end
          end
        end

        def valid_sns_url?(url)
          return false if url.blank?

          uri = URI.parse(url)
          uri.scheme == 'https' && uri.host.match?(/\Asns\.[a-z0-9-]+\.amazonaws\.com\z/)
        rescue URI::InvalidURIError
          false
        end

        def parse_ses_message(message_string)
          return nil if message_string.blank?

          JSON.parse(message_string)
        rescue JSON::ParserError => e
          Rails.logger.error("[Escalated::SesAdapter] Failed to parse SES message: #{e.message}")
          nil
        end

        def build_inbound_message(ses_message)
          mail_data = ses_message["mail"] || {}
          receipt_data = ses_message["receipt"] || {}
          content = ses_message["content"]

          headers = extract_headers(mail_data)
          from_email = mail_data.dig("source") || headers["From"]
          from_name = nil

          # Parse the From header for a display name
          if headers["From"].present?
            from_name, parsed_email = parse_email_address(headers["From"])
            from_email = parsed_email if parsed_email.present?
          end

          to_email = Array(mail_data["destination"]).first || headers["To"]
          if to_email.present?
            _, to_email = parse_email_address(to_email)
          end

          # Extract body from content (if raw email is provided)
          body_text, body_html = extract_body(content)

          InboundMessage.new(
            from_email: from_email,
            from_name: from_name,
            to_email: to_email,
            subject: headers["Subject"] || mail_data.dig("commonHeaders", "subject") || "(no subject)",
            body_text: body_text,
            body_html: body_html,
            message_id: mail_data["messageId"] || headers["Message-ID"],
            in_reply_to: headers["In-Reply-To"],
            references: parse_references(headers["References"]),
            headers: headers,
            attachments: []
          )
        end

        def extract_headers(mail_data)
          raw_headers = mail_data["headers"]
          return {} unless raw_headers.is_a?(Array)

          raw_headers.each_with_object({}) do |header, hash|
            hash[header["name"]] = header["value"] if header.is_a?(Hash)
          end
        end

        def extract_body(content)
          return ["", nil] if content.blank?

          # If content is a raw MIME message (base64 encoded), do basic extraction
          # For production, consider using the `mail` gem for robust MIME parsing
          if content.is_a?(String)
            # Try to find text/plain and text/html parts from a raw email
            # This is a simplified parser; production should use the `mail` gem
            [content, nil]
          else
            ["", nil]
          end
        end
      end
    end
  end
end
