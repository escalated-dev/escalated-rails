module Escalated
  module Services
    class InboundEmailService
      class << self
        # Process an inbound email message and create/reply to a ticket.
        #
        # @param message [Escalated::Mail::InboundMessage] the parsed email message
        # @param adapter_name [String] the name of the adapter that parsed this message
        # @return [Escalated::InboundEmail] the inbound email record
        def process(message, adapter_name: "unknown")
          unless Escalated.configuration.inbound_email_enabled
            Rails.logger.info("[Escalated::InboundEmailService] Inbound email is disabled, skipping")
            return nil
          end

          unless message.valid?
            Rails.logger.warn("[Escalated::InboundEmailService] Invalid message: missing required fields")
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
              "[Escalated::InboundEmailService] Failed to process message: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
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
            body_html: message.body_html,
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

        # Search for an existing ticket using:
        # 1. Subject line reference tag (e.g., [ESC-2602-ABC123])
        # 2. In-Reply-To / References headers matching previous message IDs
        #
        # @return [Escalated::Ticket, nil]
        def find_existing_ticket(message)
          # Strategy 1: Look for ticket reference in subject
          reference = message.ticket_reference
          if reference.present?
            ticket = Escalated::Ticket.find_by(reference: reference)
            return ticket if ticket
          end

          # Strategy 2: Look up by In-Reply-To matching a previous inbound email
          if message.in_reply_to.present?
            previous = Escalated::InboundEmail.find_by(message_id: message.in_reply_to)
            return previous.ticket if previous&.ticket
          end

          # Strategy 3: Look up by References header
          if message.references.present?
            message.references.reverse_each do |ref|
              previous = Escalated::InboundEmail.find_by(message_id: ref)
              return previous.ticket if previous&.ticket
            end
          end

          nil
        end

        # Add a reply to an existing ticket.
        # Look up the user by email; if not found, treat as guest reply.
        #
        # @return [Escalated::Reply]
        def add_reply_to_ticket(ticket, message)
          author = find_user_by_email(message.from_email)
          body = message.body

          if body.blank?
            body = "(empty reply from #{message.from_email})"
          end

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
          description = message.body

          if description.blank?
            description = "(no content)"
          end

          if user
            # Authenticated user ticket
            ticket = Services::TicketService.create(
              subject: subject,
              description: description,
              priority: Escalated.configuration.default_priority,
              requester: user,
              metadata: { channel: "email", original_message_id: message.message_id }
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
              metadata: { channel: "email", original_message_id: message.message_id }
            )

            # Dispatch notifications manually since we bypassed TicketService.create
            Services::NotificationService.dispatch(:ticket_created, ticket: ticket)
          end

          Rails.logger.info(
            "[Escalated::InboundEmailService] Created ticket #{ticket.reference} from #{message.from_email}" \
            "#{user ? '' : ' (guest)'}"
          )

          ticket
        end

        # Look up a user in the host application by email.
        #
        # @param email [String]
        # @return [User, nil]
        def find_user_by_email(email)
          return nil if email.blank?

          user_class = Escalated.configuration.user_model
          if user_class.respond_to?(:find_by)
            user_class.find_by(email: email.downcase.strip)
          else
            nil
          end
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
