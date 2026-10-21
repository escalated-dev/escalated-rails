# frozen_string_literal: true

module Escalated
  module Guest
    class TicketsController < Escalated::PublicController
      include Escalated::Renderable
      include Escalated::GuestThrottling
      include Escalated::GuestProof

      protect_from_forgery with: :exception

      before_action :ensure_guest_tickets_enabled
      before_action :throttle_guest_tickets!, only: :store
      # Before the token lookup, so requests with a wrong token count too.
      before_action :throttle_guest_replies!, only: :reply
      before_action :set_ticket_by_token, only: %i[show reply rate]
      before_action :set_inertia_shared_data, if: -> { Escalated.configuration.ui_enabled? }
      after_action :set_guest_privacy_headers

      def show
        replies = @ticket.replies
                         .where(is_internal: false, is_system: false)
                         .order(created_at: :asc)
                         .includes(:author, :attachments)

        render_page 'Escalated/Guest/Show', {
          ticket: guest_ticket_detail_json(@ticket),
          replies: replies.map { |r| guest_reply_json(r) },
          token: params[:token],
          can_reply: @ticket.open?
        }
      end

      def create
        render_page 'Escalated/Guest/Create', create_page_props
      end

      # Needs a ticket-purpose proof for the email (POST /guest/verification).
      # Redirects to the ticket page under a new, expiring grant.
      def store
        errors = validate_guest_params
        errors[:verification_code] = 'Verify your email address first.' if missing_proof?
        if errors.any?
          render_page 'Escalated/Guest/Create', create_page_props.merge(errors: errors, old: guest_ticket_params.to_h)
          return
        end

        email = Services::GuestEmailVerification.normalize(guest_email_param)

        # Dedupe repeat guests by email (Pattern B). Inline guest_*
        # fields remain populated for the backwards-compat dual-read
        # period.
        contact = Escalated::Contact.find_or_create_by_email(email, guest_name_param)

        attrs = {
          subject: guest_ticket_params[:subject],
          description: guest_ticket_params[:description],
          priority: guest_ticket_params[:priority].presence || Escalated.configuration.default_priority,
          department_id: guest_ticket_params[:department_id].presence,
          guest_name: guest_name_param,
          guest_email: email,
          contact_id: contact.id
        }

        mode = Escalated::EscalatedSetting.get('guest_policy_mode').presence || 'unassigned'
        if mode == 'guest_user'
          guest_user_id = Escalated::EscalatedSetting.get('guest_policy_user_id')
          if guest_user_id.present?
            attrs[:requester_type] = Escalated.configuration.user_class
            attrs[:requester_id] = guest_user_id
          else
            # Misconfigured guest_user mode: fall through to unassigned.
            attrs[:requester] = nil
          end
        else
          attrs[:requester] = nil
        end

        # Through TicketService so the ticket gets its SLA and the
        # ticket_created event (workflows, webhooks, notifications) fires,
        # once the ticket, its files and the consumed proof are committed.
        ticket, token = Services::GuestEmailVerification.consume(
          params[:verification_id], params[:verification_code].to_s, email, 'ticket'
        ) do
          created = Services::TicketService.create_local(attrs, announce: false)
          if guest_ticket_params[:attachments].present?
            Services::AttachmentService.attach(created, guest_ticket_params[:attachments])
          end
          [created, Escalated::GuestAccess.issue(created, email: email)]
        end
        Services::TicketService.announce_created(ticket)

        redirect_to "#{escalated_mount_path}/guest/#{token}", notice: I18n.t('escalated.guest.created')
      rescue Services::GuestEmailVerification::InvalidCode => e
        render_page 'Escalated/Guest/Create',
                    create_page_props.merge(errors: { verification_code: e.message }, old: guest_ticket_params.to_h)
      rescue Services::AttachmentService::TooManyAttachmentsError,
             Services::AttachmentService::FileTooLargeError,
             Services::AttachmentService::InvalidFileTypeError => e
        redirect_back_or_to("#{escalated_mount_path}/guest/create", alert: e.message)
      end

      def reply
        unless @ticket.open?
          redirect_to "#{escalated_mount_path}/guest/#{params[:token]}", alert: I18n.t('escalated.guest.ticket_closed')
          return
        end

        body = params[:body].to_s.strip
        if body.blank?
          redirect_to "#{escalated_mount_path}/guest/#{params[:token]}"
          return
        end

        reply = Escalated::Reply.create!(
          ticket: @ticket,
          author: nil,
          body: body,
          is_internal: false,
          is_system: false
        )

        # Update ticket status if waiting on customer
        @ticket.update!(status: :open) if @ticket.waiting_on_customer?

        Services::AttachmentService.attach(reply, params[:attachments]) if params[:attachments].present?

        redirect_to "#{escalated_mount_path}/guest/#{params[:token]}", notice: I18n.t('escalated.ticket.reply_sent')
      rescue Services::AttachmentService::TooManyAttachmentsError,
             Services::AttachmentService::FileTooLargeError,
             Services::AttachmentService::InvalidFileTypeError => e
        redirect_to "#{escalated_mount_path}/guest/#{params[:token]}", alert: e.message
      end

      def rate
        unless %w[resolved closed].include?(@ticket.status)
          redirect_to "#{escalated_mount_path}/guest/#{params[:token]}",
                      alert: I18n.t('escalated.rating.only_resolved_closed')
          return
        end

        if @ticket.satisfaction_rating.present?
          redirect_to "#{escalated_mount_path}/guest/#{params[:token]}",
                      alert: I18n.t('escalated.rating.already_rated')
          return
        end

        rating = Escalated::SatisfactionRating.new(
          ticket: @ticket,
          rating: params[:rating].to_i,
          comment: params[:comment]
        )

        if rating.save
          redirect_to "#{escalated_mount_path}/guest/#{params[:token]}",
                      notice: I18n.t('escalated.rating.thanks')
        else
          redirect_to "#{escalated_mount_path}/guest/#{params[:token]}",
                      alert: rating.errors.full_messages.join(', ')
        end
      end

      private

      def ensure_guest_tickets_enabled
        return if Escalated::EscalatedSetting.guest_tickets_enabled?

        render plain: I18n.t('escalated.commands.guest_not_enabled'), status: :not_found
      end

      # An expiring grant, or a legacy guest_token while those are accepted.
      def set_ticket_by_token
        @ticket = Escalated::GuestAccess.find_ticket(params[:token])
        return if @ticket

        render plain: I18n.t('escalated.commands.ticket_not_found'), status: :not_found
      end

      def create_page_props
        {
          departments: Escalated::Department.active.ordered.map { |d| { id: d.id, name: d.name } },
          priorities: Escalated::Ticket.priorities.keys,
          default_priority: Escalated.configuration.default_priority.to_s,
          verification_url: "#{escalated_mount_path}/guest/verification",
          lookup_url: "#{escalated_mount_path}/guest/lookup"
        }
      end

      def missing_proof?
        params[:verification_id].blank? || params[:verification_code].blank?
      end

      # Guest/Create posts guest_name and guest_email; name and email are
      # still read for older forms.
      def guest_name_param
        params[:guest_name].presence || guest_ticket_params[:name]
      end

      def guest_email_param
        params[:guest_email].presence || guest_ticket_params[:email]
      end

      def set_inertia_shared_data
        inertia_share(
          escalated: {
            route_prefix: Escalated.configuration.route_prefix,
            guest_tickets_enabled: Escalated::EscalatedSetting.guest_tickets_enabled?
          },
          flash: {
            success: flash[:success],
            error: flash[:error],
            notice: flash[:notice],
            alert: flash[:alert]
          }
        )
      end

      def guest_ticket_params
        params.permit(:name, :email, :guest_name, :guest_email, :subject, :description, :priority, :department_id,
                      attachments: [])
      end

      def validate_guest_params
        errors = {}
        errors[:guest_name] = I18n.t('escalated.validation.name_required') if guest_name_param.blank?
        errors[:guest_email] = I18n.t('escalated.validation.email_required') if guest_email_param.blank?
        errors[:subject] = I18n.t('escalated.validation.subject_required') if guest_ticket_params[:subject].blank?
        if guest_ticket_params[:description].blank?
          errors[:description] =
            I18n.t('escalated.validation.description_required')
        end
        errors
      end

      def escalated_mount_path
        "/#{Escalated.configuration.route_prefix}"
      end

      def guest_ticket_json(ticket)
        {
          id: ticket.id,
          reference: ticket.reference,
          subject: ticket.subject,
          description: ticket.description,
          status: ticket.status,
          priority: ticket.priority,
          is_guest: ticket.guest?,
          guest_name: ticket.guest_name,
          guest_email: ticket.guest_email,
          requester_name: ticket.requester_name,
          requester_email: ticket.requester_email,
          last_reply_at: ticket.last_reply_at&.iso8601,
          last_reply_author: ticket.last_reply_author,
          is_live_chat: ticket.is_live_chat,
          is_snoozed: ticket.is_snoozed,
          department: ticket.department ? { id: ticket.department.id, name: ticket.department.name } : nil,
          created_at: ticket.created_at&.iso8601,
          updated_at: ticket.updated_at&.iso8601,
          attachments: ticket.attachments.map do |a|
            { id: a.id, filename: a.filename, size: a.human_size, content_type: a.content_type,
              url: Services::AttachmentService.url_for(a, guest_ticket: ticket) }
          end,
          satisfaction_rating: if ticket.satisfaction_rating
                                 {
                                   id: ticket.satisfaction_rating.id,
                                   rating: ticket.satisfaction_rating.rating,
                                   comment: ticket.satisfaction_rating.comment,
                                   created_at: ticket.satisfaction_rating.created_at&.iso8601
                                 }
                               end
        }
      end

      def guest_ticket_detail_json(ticket)
        base = guest_ticket_json(ticket)

        if ticket.chat?
          session = ticket.active_chat_session || ticket.chat_sessions.order(created_at: :desc).first
          base.merge!(
            chat_session_id: session&.id,
            chat_started_at: session&.started_at&.iso8601,
            chat_messages: ticket.replies.where(is_internal: false, is_system: false)
                                 .order(created_at: :asc).includes(:author).map { |r| guest_chat_message_json(r) },
            chat_metadata: session&.metadata
          )
        end

        base
      end

      def guest_chat_message_json(reply)
        author_name = if reply.author
                        reply.author.respond_to?(:name) ? reply.author.name : reply.author&.email
                      else
                        @ticket.guest_name || 'Guest'
                      end

        {
          id: reply.id,
          body: reply.body,
          is_internal_note: false,
          is_agent: reply.author.respond_to?(:escalated_agent?) ? reply.author.escalated_agent? : false,
          author: { name: author_name },
          created_at: reply.created_at&.iso8601
        }
      end

      def guest_reply_json(reply)
        author_name = if reply.author
                        reply.author.respond_to?(:name) ? reply.author.name : reply.author&.email
                      else
                        @ticket.guest_name || 'Guest'
                      end

        {
          id: reply.id,
          body: reply.body,
          author: {
            name: author_name,
            is_agent: reply.author.respond_to?(:escalated_agent?) ? reply.author.escalated_agent? : false
          },
          attachments: reply.attachments.map do |a|
            { id: a.id, filename: a.filename, size: a.human_size, content_type: a.content_type,
              url: Services::AttachmentService.url_for(a, guest_ticket: @ticket) }
          end,
          created_at: reply.created_at&.iso8601,
          is_system: reply.is_system
        }
      end
    end
  end
end
