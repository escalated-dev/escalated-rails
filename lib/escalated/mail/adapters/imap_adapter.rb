require "net/imap"

module Escalated
  module Mail
    module Adapters
      class ImapAdapter < BaseAdapter
        # The IMAP adapter does not parse HTTP requests.
        # Instead, it provides methods to poll an IMAP mailbox.
        #
        # @param request [ActionDispatch::Request] unused for IMAP
        # @return [nil]
        def parse_request(request)
          raise NotImplementedError,
            "ImapAdapter does not support webhook parsing. Use #fetch_messages instead."
        end

        # IMAP does not use webhook verification.
        def verify_request(request)
          false
        end

        # Connect to the configured IMAP server and fetch unread messages.
        #
        # @return [Array<Escalated::Mail::InboundMessage>]
        def fetch_messages
          messages = []
          config = imap_config

          imap = connect(config)
          return messages unless imap

          begin
            imap.login(config[:username], config[:password])
            imap.select(config[:mailbox])

            # Search for unseen (unread) messages
            uids = imap.uid_search(["UNSEEN"])

            uids.each do |uid|
              message = fetch_message(imap, uid)
              messages << message if message
            end
          rescue Net::IMAP::Error => e
            Rails.logger.error("[Escalated::ImapAdapter] IMAP error: #{e.message}")
          ensure
            begin
              imap.logout
              imap.disconnect
            rescue StandardError
              # Ignore disconnect errors
            end
          end

          messages
        end

        # Mark a message as seen/read on the IMAP server.
        #
        # @param uid [Integer] the UID of the message to mark
        def mark_as_read(uid)
          config = imap_config
          imap = connect(config)
          return unless imap

          begin
            imap.login(config[:username], config[:password])
            imap.select(config[:mailbox])
            imap.uid_store(uid, "+FLAGS", [:Seen])
          rescue Net::IMAP::Error => e
            Rails.logger.error("[Escalated::ImapAdapter] Failed to mark message #{uid} as read: #{e.message}")
          ensure
            begin
              imap.logout
              imap.disconnect
            rescue StandardError
              # Ignore disconnect errors
            end
          end
        end

        private

        def imap_config
          config = Escalated.configuration
          {
            host: config.imap_host,
            port: config.imap_port || 993,
            encryption: config.imap_encryption || :ssl,
            username: config.imap_username,
            password: config.imap_password,
            mailbox: config.imap_mailbox || "INBOX"
          }
        end

        def connect(config)
          return nil if config[:host].blank? || config[:username].blank? || config[:password].blank?

          ssl = config[:encryption] == :ssl || config[:encryption] == :tls
          Net::IMAP.new(config[:host], port: config[:port], ssl: ssl)
        rescue SocketError, Errno::ECONNREFUSED, Net::IMAP::Error => e
          Rails.logger.error("[Escalated::ImapAdapter] Connection failed: #{e.message}")
          nil
        end

        def fetch_message(imap, uid)
          fetch_data = imap.uid_fetch(uid, ["ENVELOPE", "BODY[TEXT]", "BODY[HEADER]", "RFC822"])
          return nil unless fetch_data&.first

          data = fetch_data.first
          envelope = data.attr["ENVELOPE"]
          raw_body = data.attr["BODY[TEXT]"] || ""
          raw_headers = data.attr["BODY[HEADER]"] || ""
          rfc822 = data.attr["RFC822"] || ""

          from = envelope.from&.first
          to = envelope.to&.first

          from_email = from ? "#{from.mailbox}@#{from.host}" : nil
          from_name = from&.name
          to_email = to ? "#{to.mailbox}@#{to.host}" : nil

          # Parse headers for In-Reply-To and References
          headers = parse_raw_headers(raw_headers)

          # Extract plain text body
          body_text, body_html = extract_body_parts(rfc822)

          message = InboundMessage.new(
            from_email: from_email,
            from_name: from_name,
            to_email: to_email,
            subject: envelope.subject || "(no subject)",
            body_text: body_text.presence || raw_body,
            body_html: body_html,
            message_id: envelope.message_id,
            in_reply_to: envelope.in_reply_to,
            references: parse_references(headers["References"]),
            headers: headers,
            attachments: []
          )

          # Mark the message as seen after successful fetch
          imap.uid_store(uid, "+FLAGS", [:Seen])

          message
        rescue StandardError => e
          Rails.logger.error("[Escalated::ImapAdapter] Failed to fetch message #{uid}: #{e.message}")
          nil
        end

        def parse_raw_headers(raw_headers)
          return {} if raw_headers.blank?

          headers = {}
          current_key = nil
          current_value = nil

          raw_headers.each_line do |line|
            if line =~ /\A(\S+):\s*(.*)/
              headers[current_key] = current_value.strip if current_key
              current_key = $1
              current_value = $2
            elsif line =~ /\A\s+(.*)/
              # Continuation of previous header
              current_value = "#{current_value} #{$1}" if current_key
            end
          end

          headers[current_key] = current_value.strip if current_key
          headers
        end

        def extract_body_parts(rfc822)
          return ["", nil] if rfc822.blank?

          # Simple MIME extraction — for production, use the `mail` gem
          # This handles the common case of plain text emails
          body_text = ""
          body_html = nil

          # Check for multipart boundary
          if rfc822 =~ /Content-Type:.*?boundary="?([^";\s]+)"?/mi
            boundary = $1
            parts = rfc822.split("--#{boundary}")

            parts.each do |part|
              if part =~ /Content-Type:\s*text\/plain/i
                body_text = extract_part_body(part)
              elsif part =~ /Content-Type:\s*text\/html/i
                body_html = extract_part_body(part)
              end
            end
          else
            # No multipart — treat the whole body as text
            body_text = rfc822.sub(/\A.*?\r?\n\r?\n/m, "")
          end

          [body_text, body_html]
        end

        def extract_part_body(part)
          # Skip headers, extract body after blank line
          body = part.sub(/\A.*?\r?\n\r?\n/m, "")
          body&.strip || ""
        end
      end
    end
  end
end
