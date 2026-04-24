# frozen_string_literal: true

require 'escalated/mail/message_id_util'

module Escalated
  module Services
    class InboundEmailService
      ALLOWED_TAGS = %w[p br b strong i em u a ul ol li h1 h2 h3 h4 h5 h6 blockquote pre code table thead tbody tr th
                        td img hr div span sub sup].freeze

      BLOCKED_EXTENSIONS = %w[
        exe bat cmd com msi scr pif vbs vbe
        js jse wsf wsh ps1 psm1 psd1 reg
        cpl hta inf lnk sct shb sys drv
        php phtml php3 php4 php5 phar
        sh bash csh ksh pl py rb
        dll so dylib
      ].freeze

      class << self
        # Process an inbound email message and create/reply to a ticket.
        #
        # @param message [Escalated::Mail::InboundMessage] the parsed email message
        # @param adapter_name [String] the name of the adapter that parsed this message
        # @return [Escalated::InboundEmail] the inbound email record
        def process(message, adapter_name: 'unknown')
          unless Escalated.configuration.inbound_email_enabled
            Rails.logger.info('[Escalated::InboundEmailService] Inbound email is disabled, skipping')
            return nil
          end

          unless message.valid?
            Rails.logger.warn('[Escalated::InboundEmailService] Invalid message: missing required fields')
            return nil
          end

          # Create the inbound email record for tracking
          inbound_email = create_inbound_record(message, adapter_name)

          # Check for duplicate by message_id
          if inbound_email.duplicate?
            Rails.logger.info("[Escalated::InboundEmailService] Duplicate message_id: #{message.message_id}")
            inbound_email.mark_failed!("Duplicate message_id: #{message.message_id}")
            return inbound_email
          end

          begin
            ActiveRecord::Base.transaction do
              ticket, reply = resolve_and_process(message)
              inbound_email.mark_processed!(ticket: ticket, reply: reply)
            end
          rescue StandardError => e
            Rails.logger.error(
              '[Escalated::InboundEmailService] Failed to process message: ' \
              "#{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
            )
            inbound_email.mark_failed!(e.message)
          end

          inbound_email
        end

        private

        # Create the inbound email tracking record.
        def create_inbound_record(message, adapter_name)
          Escalated::InboundEmail.create!(
            message_id: message.message_id,
            from_email: message.from_email,
            from_name: message.from_name,
            to_email: message.to_email,
            subject: message.subject,
            body_text: message.body_text,
            body_html: sanitize_html(message.body_html),
            raw_headers: message.raw_headers_string,
            adapter: adapter_name,
            status: :pending
          )
        end

        # Determine whether this is a reply to an existing ticket or a new ticket,
        # then process accordingly.
        #
        # @return [Array(Ticket, Reply|nil)] the ticket and optional reply
        def resolve_and_process(message)
          # Try to find an existing ticket by subject reference
          ticket = find_existing_ticket(message)

          if ticket
            reply = add_reply_to_ticket(ticket, message)
            [ticket, reply]
          else
            ticket = create_new_ticket(message)
            [ticket, nil]
          end
        end

        # Search for an existing ticket in priority order:
        #
        # 1. In-Reply-To parsed via MessageIdUtil — the reply is
        #    threading off a Message-ID we issued (cold-start path,
        #    no DB lookup required).
        # 2. References parsed via MessageIdUtil, each id in order.
        # 3. Signed Reply-To on the recipient address
        #    (reply+{id}.{hmac8}@...) verified via
        #    MessageIdUtil.verify_reply_to. Survives through clients
        #    that strip our threading headers; forged signatures are
        #    rejected.
        # 4. Subject line reference tag (e.g., [ESC-2602-ABC123]).
        # 5. Legacy: InboundEmail.message_id lookup.
        #
        # @return [Escalated::Ticket, nil]
        def find_existing_ticket(message)
          # Strategies 1 + 2: parse our own Message-IDs.
          candidate_header_message_ids(message).each do |raw|
            ticket_id = Escalated::Mail::MessageIdUtil.parse_ticket_id_from_message_id(raw)
            next if ticket_id.nil?

            ticket = Escalated::Ticket.find_by(id: ticket_id)
            return ticket if ticket
          end

          # Strategy 3: signed Reply-To on recipient address.
          secret = Escalated.configuration.email_inbound_secret.to_s
          if !secret.empty? && message.to_email.present?
            verified = Escalated::Mail::MessageIdUtil.verify_reply_to(message.to_email, secret)
            if verified
              ticket = Escalated::Ticket.find_by(id: verified)
              return ticket if ticket
            end
          end

          # Strategy 4: subject reference tag.
          reference = message.ticket_reference
          if reference.present?
            ticket = Escalated::Ticket.find_by(reference: reference)
            return ticket if ticket
          end

          # Strategy 5: legacy InboundEmail lookup.
          candidate_header_message_ids(message).each do |raw|
            previous = Escalated::InboundEmail.find_by(message_id: raw)
            return previous.ticket if previous&.ticket
          end

          nil
        end

        # @return [Array<String>] every candidate Message-ID in the
        #   inbound headers, in the order the mail client sent them.
        def candidate_header_message_ids(message)
          ids = []
          ids << message.in_reply_to if message.in_reply_to.present?
          ids.concat(Array(message.references).reverse) if message.references.present?
          ids
        end

        # Add a reply to an existing ticket.
        # Look up the user by email; if not found, treat as guest reply.
        #
        # @return [Escalated::Reply]
        def add_reply_to_ticket(ticket, message)
          author = find_user_by_email(message.from_email)
          body = get_sanitized_body(message)

          body = "(empty reply from #{message.from_email})" if body.blank?

          reply = Services::TicketService.reply(ticket, {
                                                  body: body,
                                                  author: author,
                                                  is_internal: false,
                                                  is_system: false
                                                })

          Rails.logger.info(
            "[Escalated::InboundEmailService] Added reply to ticket #{ticket.reference} from #{message.from_email}"
          )

          reply
        end

        # Create a new ticket from the inbound email.
        # Look up the user by email; if not found, create as guest ticket.
        #
        # @return [Escalated::Ticket]
        def create_new_ticket(message)
          user = find_user_by_email(message.from_email)
          subject = message.clean_subject.presence || message.subject
          description = get_sanitized_body(message)

          description = '(no content)' if description.blank?

          if user
            # Authenticated user ticket
            ticket = Services::TicketService.create(
              subject: subject,
              description: description,
              priority: Escalated.configuration.default_priority,
              requester: user,
              metadata: { channel: 'email', original_message_id: message.message_id }
            )
          else
            # Guest ticket (follows guest/tickets_controller.rb pattern)
            guest_token = SecureRandom.hex(32)

            ticket = Escalated::Ticket.create!(
              requester: nil,
              guest_name: message.from_name || message.from_email,
              guest_email: message.from_email,
              guest_token: guest_token,
              subject: subject,
              description: description,
              priority: Escalated.configuration.default_priority,
              metadata: { channel: 'email', original_message_id: message.message_id }
            )

            # Dispatch notifications manually since we bypassed TicketService.create
            Services::NotificationService.dispatch(:ticket_created, ticket: ticket)
          end

          Rails.logger.info(
            "[Escalated::InboundEmailService] Created ticket #{ticket.reference} from #{message.from_email}" \
            "#{' (guest)' unless user}"
          )

          ticket
        end

        def sanitize_html(html)
          return html if html.blank?

          # Use Rails' built-in sanitizer if available
          if defined?(ActionView::Base)
            ActionView::Base.safe_list_sanitizer.new.sanitize(
              html,
              tags: ALLOWED_TAGS,
              attributes: %w[href src alt title class style id]
            )
          else
            # Fallback: strip all tags except allowed
            clean = html.dup
            # Remove script tags and their content
            clean.gsub!(%r{<script\b[^>]*>.*?</script>}mi, '')
            # Remove event handlers
            clean.gsub!(/\s+on\w+\s*=\s*["'][^"']*["']/i, '')
            clean.gsub!(/\s+on\w+\s*=\s*\S+/i, '')
            # Remove javascript: protocol
            clean.gsub!(/\b(href|src|action)\s*=\s*["']?\s*javascript\s*:/i, '\1="')
            # Remove dangerous data: URLs
            clean.gsub!(%r{\b(href|src|action)\s*=\s*["']?\s*data\s*:(?!image/)}i, '\1="')
            clean
          end
        end

        def get_sanitized_body(message)
          if message.body_text.present?
            message.body_text
          elsif message.body_html.present?
            sanitize_html(message.body_html) || ''
          else
            ''
          end
        end

        # Look up a user in the host application by email.
        #
        # @param email [String]
        # @return [User, nil]
        def find_user_by_email(email)
          return nil if email.blank?

          user_class = Escalated.configuration.user_model
          user_class.find_by(email: email.downcase.strip) if user_class.respond_to?(:find_by)
        rescue StandardError => e
          Rails.logger.warn(
            "[Escalated::InboundEmailService] Failed to look up user by email: #{e.message}"
          )
          nil
        end
      end
    end
  end
end
