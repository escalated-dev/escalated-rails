# frozen_string_literal: true

module Escalated
  module Api
    module V1
      # The mobile guest API under <api_prefix>/mobile/guest, drawn only while
      # the REST API is enabled. The canonical contract is
      # escalated-developer-context domain-model/mobile-guest-api.md; Laravel's
      # MobileGuestTicketController is the port of record.
      #
      # It is the mobile face of verified guest access: the same email codes
      # (GuestEmailVerification), the same grants (GuestAccess), the same
      # verification and lookup handlers and the same per-IP guest budgets as
      # the guest pages and the widget. Only the payload shapes differ.
      class MobileGuestController < ActionController::API
        include Escalated::ApiRateLimiting
        include Escalated::GuestThrottling

        MAX_ATTACHMENTS = 10
        PRIORITIES = %w[low medium high urgent critical].freeze
        UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
        STATUS_LABELS = {
          'open' => 'Open', 'in_progress' => 'In Progress', 'waiting_on_customer' => 'Waiting on Customer',
          'waiting_on_agent' => 'Waiting on Agent', 'escalated' => 'Escalated', 'resolved' => 'Resolved',
          'closed' => 'Closed', 'reopened' => 'Reopened', 'live' => 'Live'
        }.freeze
        ATTACHMENT_ERRORS = [
          Escalated::Services::AttachmentService::TooManyAttachmentsError,
          Escalated::Services::AttachmentService::FileTooLargeError,
          Escalated::Services::AttachmentService::InvalidFileTypeError
        ].freeze

        # In this order: every answer, errors and 429s included, carries the
        # privacy headers; then the API limiter, then the guest budgets.
        before_action :set_guest_privacy_headers
        before_action :check_api_enabled!
        before_action :enforce_rate_limit!
        before_action :throttle_guest_requests!
        include Escalated::GuestVerificationEndpoints

        before_action :throttle_guest_tickets!, only: :create_ticket
        # Before the grant is resolved, so requests with a bad grant count too.
        before_action :throttle_guest_replies!, only: :reply

        # POST verification and POST lookup are GuestVerificationEndpoints'
        # handlers, shared with the guest pages and the widget.

        # POST <prefix>/mobile/guest/tickets
        def create_ticket
          unless guest_tickets_allowed?
            return render json: { message: 'Guest tickets are not enabled.' }, status: :forbidden
          end

          errors = ticket_errors
          return render_validation_errors(errors) if errors.any?

          email = Services::GuestEmailVerification.normalize(params[:email])
          ticket, token = with_guest_proof('ticket', email) { create_guest_ticket(email) }
          return if performed?

          Services::TicketService.announce_created(ticket)
          render json: { data: mobile_ticket(ticket, token), message: 'Ticket created.' }, status: :created
        rescue *ATTACHMENT_ERRORS => e
          render_validation_errors(attachments: [e.message])
        end

        # GET <prefix>/mobile/guest/tickets/:token
        def show_ticket
          ticket = granted_ticket
          return render_not_found unless ticket

          render json: { data: mobile_ticket(ticket, params[:token], replies: true) }
        end

        # POST <prefix>/mobile/guest/tickets/:token/replies
        def reply
          ticket = granted_ticket
          return render_not_found unless ticket
          return render json: { message: 'This ticket is closed.' }, status: :unprocessable_content if ticket.closed?

          errors = reply_errors
          return render_validation_errors(errors) if errors.any?

          unless email_matches?(ticket)
            return render json: { message: 'The provided email does not match this ticket.' }, status: :forbidden
          end

          store_reply(ticket)
          render json: { message: 'Reply sent.' }, status: :created
        rescue *ATTACHMENT_ERRORS => e
          render_validation_errors(attachments: [e.message])
        end

        private

        def check_api_enabled!
          return if Escalated.configuration.api_enabled

          render json: { message: 'API is not enabled.' }, status: :not_found
        end

        # Laravel's GuestPrivacyHeaders. Also called after the shared
        # verification and lookup handlers.
        def set_guest_privacy_headers
          response.cache_control.replace(private: true, no_store: true)
          response.headers['Referrer-Policy'] = 'no-referrer'
        end

        def guest_throttle_json?
          true
        end

        # A ticket-purpose grant only: a chat grant, a legacy guest_token and
        # anything expired, rotated, revoked or malformed are all a 404.
        def granted_ticket
          Escalated::GuestAccess.resolve(params[:token])
        end

        def render_not_found
          render json: { message: 'Not found.' }, status: :not_found
        end

        def render_validation_errors(errors)
          render json: { message: errors.values.first.first, errors: errors }, status: :unprocessable_content
        end

        def ticket_errors
          errors = {}
          require_string(errors, :name, 255)
          require_email(errors, 255)
          require_string(errors, :subject, 255)
          require_string(errors, :description, 65_535)
          unless params[:verification_id].to_s.match?(UUID)
            errors[:verification_id] = ['The verification id must be a valid UUID.']
          end
          require_string(errors, :verification_code, 16)
          if params[:priority].present? && PRIORITIES.exclude?(params[:priority].to_s)
            errors[:priority] = ['The selected priority is invalid.']
          end
          if params[:department_id].present? && !Escalated::Department.exists?(id: params[:department_id].to_s)
            errors[:department_id] = ['The selected department is invalid.']
          end
          attachment_errors(errors)
          errors
        end

        def reply_errors
          errors = {}
          require_string(errors, :body, 65_535)
          require_email(errors, nil)
          attachment_errors(errors)
          errors
        end

        def require_string(errors, key, max)
          value = params[key]
          if !value.is_a?(String) || value.strip.empty?
            errors[key] = ["The #{key.to_s.humanize(capitalize: false)} field is required."]
          elsif value.length > max
            errors[key] = ["The #{key.to_s.humanize(capitalize: false)} may not be greater than #{max} characters."]
          end
        end

        def require_email(errors, max)
          value = params[:email]
          normalized = Services::GuestEmailVerification.normalize(value)
          valid = value.is_a?(String) && normalized.match?(Services::GuestEmailVerification::EMAIL) &&
                  (max.nil? || value.length <= max)
          errors[:email] = ['The email must be a valid email address.'] unless valid
        end

        # Checked up front so nothing is stored when a file would be refused.
        # The count is capped at 10 and at the port's max_attachments.
        def attachment_errors(errors)
          files = uploaded_attachments
          return if files.nil?

          max = [MAX_ATTACHMENTS, Escalated.configuration.max_attachments.to_i].min
          message = if files.size > max
                      "No more than #{max} attachments are allowed."
                    elsif files.any? { |file| !file.respond_to?(:original_filename) }
                      'Each attachment must be a file.'
                    else
                      files.lazy.map { |file| attachment_problem(file) }.find(&:itself)
                    end
          errors[:attachments] = [message] if message
        end

        def attachment_problem(file)
          max_kb = Escalated.configuration.max_attachment_size_kb.to_i
          if file.size > max_kb * 1024
            "The file #{file.original_filename} is larger than #{max_kb} KB."
          elsif Services::AttachmentService::ALLOWED_CONTENT_TYPES.exclude?(file.content_type)
            "The file type #{file.content_type} is not allowed."
          end
        end

        def uploaded_attachments
          files = params[:attachments]
          return nil if files.blank?

          files.is_a?(Array) ? files : [files]
        end

        # Runs inside the proof's transaction: a failure rolls the contact,
        # ticket and attachments back and hands the code back.
        def create_guest_ticket(email)
          contact = Escalated::Contact.find_or_create_by_email(email, params[:name])
          attrs = apply_guest_policy(
            subject: params[:subject], description: params[:description],
            priority: params[:priority].presence || Escalated.configuration.default_priority,
            department_id: params[:department_id].presence, guest_name: params[:name], guest_email: email,
            contact_id: contact.id, channel: 'web'
          )
          ticket = Services::TicketService.create_local(attrs, announce: false)
          files = uploaded_attachments
          Services::AttachmentService.attach(ticket, files) if files.present?
          [ticket, Escalated::GuestAccess.issue(ticket, email: email)]
        end

        # The admin's guest policy, as the guest form and the widget apply it.
        def apply_guest_policy(attrs)
          mode = Escalated::EscalatedSetting.get('guest_policy_mode').presence || 'unassigned'
          guest_user_id = Escalated::EscalatedSetting.get('guest_policy_user_id')
          if mode == 'guest_user' && guest_user_id.present?
            attrs.merge(requester_type: Escalated.configuration.user_class, requester_id: guest_user_id)
          else
            attrs.merge(requester: nil)
          end
        end

        # A second factor on top of the grant, not a substitute for it.
        def email_matches?(ticket)
          ActiveSupport::SecurityUtils.secure_compare(
            Services::GuestEmailVerification.normalize(ticket.guest_email),
            Services::GuestEmailVerification.normalize(params[:email])
          )
        end

        # A public reply with no author (the guest), through TicketService so
        # the normal reply handling (event, mail, broadcast) runs.
        def store_reply(ticket)
          reply = Services::TicketService.reply(ticket, body: params[:body], author: nil, is_internal: false)
          files = uploaded_attachments
          Services::AttachmentService.attach(reply, files) if files.present?
        end

        # The allow-listed mobile ticket object. Never the model: no
        # external_reference, chat metadata, internal notes or staff emails.
        def mobile_ticket(ticket, token, replies: false)
          {
            id: ticket.id,
            reference: ticket.reference,
            guest_access_token: token,
            guest_access_expires_at: token ? ticket.guest_access_expires_at&.iso8601 : nil,
            subject: ticket.subject,
            description: ticket.description.to_s,
            status: { value: ticket.status, label: STATUS_LABELS.fetch(ticket.status, ticket.status.to_s.titleize) },
            priority: { value: ticket.priority, label: ticket.priority.to_s.titleize },
            channel: ticket.channel,
            metadata: {},
            requester: { name: ticket.guest_name.presence || 'Guest', email: ticket.guest_email },
            assignee: ticket.assigned_to.present? ? staff(ticket.assignee) : nil,
            department: ticket.department ? { id: ticket.department.id, name: ticket.department.name } : nil,
            tags: [],
            replies: replies ? mobile_replies(ticket) : [],
            activities: [],
            sla: {
              first_response_due_at: ticket.sla_first_response_due_at&.iso8601,
              first_response_at: ticket.first_response_at&.iso8601,
              first_response_breached: ticket.sla_first_response_breached? == true,
              resolution_due_at: ticket.sla_resolution_due_at&.iso8601,
              resolution_breached: ticket.sla_resolution_breached? == true
            },
            is_following: false,
            followers_count: 0,
            resolved_at: ticket.resolved_at&.iso8601,
            closed_at: ticket.closed_at&.iso8601,
            created_at: ticket.created_at&.iso8601,
            updated_at: ticket.updated_at&.iso8601
          }
        end

        def mobile_replies(ticket)
          ticket.replies.public_replies.reverse_chronological.order(id: :desc)
                .includes(:author, :attachments).map do |reply|
            {
              id: reply.id,
              body: reply.body.to_s,
              is_internal_note: false,
              is_pinned: reply.is_pinned == true,
              author: reply.author ? staff(reply.author) : guest_author(ticket),
              attachments: reply.attachments.map { |attachment| mobile_attachment(attachment, ticket) },
              created_at: reply.created_at&.iso8601
            }
          end
        end

        def mobile_attachment(attachment, ticket)
          {
            id: attachment.id,
            filename: attachment.filename,
            mime_type: attachment.content_type,
            size: attachment.byte_size,
            url: Services::AttachmentService.url_for(attachment, guest_ticket: ticket)
          }
        end

        def guest_author(ticket)
          { id: 0, name: ticket.guest_name.presence || 'Guest', email: ticket.guest_email.to_s }
        end

        # Staff appear by display name only.
        def staff(user)
          name = user.respond_to?(:name) ? user.name.presence : nil if user
          { id: 0, name: name || 'Support', email: '' }
        end
      end
    end
  end
end
