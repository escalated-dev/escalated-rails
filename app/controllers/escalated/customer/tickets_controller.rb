# frozen_string_literal: true

module Escalated
  module Customer
    class TicketsController < Escalated::ApplicationController
      before_action :set_ticket, only: %i[show reply close reopen]

      def index
        scope = Escalated::Ticket.where(
          requester: escalated_current_user
        ).recent

        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.search(params[:search]) if params[:search].present?

        result = paginate(scope)

        render_page 'Escalated/Customer/Index', {
          tickets: result[:data].map { |t| ticket_json(t) },
          meta: result[:meta],
          filters: {
            status: params[:status],
            search: params[:search]
          }
        }
      end

      def show
        authorize @ticket, policy_class: Escalated::TicketPolicy

        replies = @ticket.replies
                         .public_replies
                         .chronological
                         .includes(:author, :attachments)

        ticket_data = ticket_detail_json(@ticket)

        render_page 'Escalated/Customer/Show', {
          ticket: ticket_data,
          replies: replies.map { |r| reply_json(r) },
          can_close: Escalated.configuration.allow_customer_close && @ticket.open?,
          can_reopen: %w[resolved closed].include?(@ticket.status)
        }
      end

      def create
        render_page 'Escalated/Customer/Create', {
          departments: Escalated::Department.active.ordered.map do |d|
            { id: d.id, name: d.name }
          end,
          priorities: Escalated::Ticket.priorities.keys,
          default_priority: Escalated.configuration.default_priority.to_s
        }
      end

      def store
        ticket = Services::TicketService.create(
          subject: ticket_params[:subject],
          description: ticket_params[:description],
          priority: ticket_params[:priority] || Escalated.configuration.default_priority,
          department_id: ticket_params[:department_id],
          requester: escalated_current_user,
          metadata: {}
        )

        Services::AttachmentService.attach(ticket, ticket_params[:attachments]) if ticket_params[:attachments].present?

        redirect_to customer_ticket_path(ticket), notice: I18n.t('escalated.ticket.created')
      rescue Services::AttachmentService::TooManyAttachmentsError,
             Services::AttachmentService::FileTooLargeError,
             Services::AttachmentService::InvalidFileTypeError => e
        redirect_back_or_to(new_customer_ticket_path, alert: e.message)
      end

      def reply
        authorize @ticket, policy_class: Escalated::TicketPolicy

        reply = Services::TicketService.reply(@ticket, {
                                                body: params[:body],
                                                author: escalated_current_user,
                                                is_internal: false
                                              })

        Services::AttachmentService.attach(reply, params[:attachments]) if params[:attachments].present?

        redirect_to customer_ticket_path(@ticket), notice: I18n.t('escalated.ticket.reply_sent')
      rescue Services::AttachmentService::TooManyAttachmentsError,
             Services::AttachmentService::FileTooLargeError,
             Services::AttachmentService::InvalidFileTypeError => e
        redirect_to customer_ticket_path(@ticket), alert: e.message
      end

      def close
        authorize @ticket, policy_class: Escalated::TicketPolicy

        unless Escalated.configuration.allow_customer_close
          redirect_to customer_ticket_path(@ticket), alert: I18n.t('escalated.ticket.customers_cannot_close')
          return
        end

        Services::TicketService.close(@ticket, actor: escalated_current_user)
        redirect_to customer_ticket_path(@ticket), notice: I18n.t('escalated.ticket.closed')
      end

      def reopen
        authorize @ticket, policy_class: Escalated::TicketPolicy

        Services::TicketService.reopen(@ticket, actor: escalated_current_user)
        redirect_to customer_ticket_path(@ticket), notice: I18n.t('escalated.ticket.reopened')
      end

      private

      def set_ticket
        @ticket = Escalated::Ticket.find(params[:id])
      end

      def ticket_params
        params.expect(ticket: [:subject, :description, :priority, :department_id, { attachments: [] }])
      end

      def ticket_json(ticket)
        {
          id: ticket.id,
          reference: ticket.reference,
          subject: ticket.subject,
          description: ticket.description,
          status: ticket.status,
          priority: ticket.priority,
          requester_name: ticket.requester_name,
          requester_email: ticket.requester_email,
          last_reply_at: ticket.last_reply_at&.iso8601,
          last_reply_author: ticket.last_reply_author,
          is_live_chat: ticket.is_live_chat,
          is_snoozed: ticket.is_snoozed,
          department: ticket.department ? { id: ticket.department.id, name: ticket.department.name } : nil,
          created_at: ticket.created_at&.iso8601,
          updated_at: ticket.updated_at&.iso8601,
          resolved_at: ticket.resolved_at&.iso8601,
          reply_count: ticket.replies.public_replies.count,
          attachments: ticket.attachments.map do |a|
            { id: a.id, filename: a.filename, size: a.human_size, content_type: a.content_type,
              url: Services::AttachmentService.url_for(a) }
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

      def ticket_detail_json(ticket)
        base = ticket_json(ticket)

        if ticket.chat?
          session = ticket.active_chat_session || ticket.chat_sessions.order(created_at: :desc).first
          base.merge!(
            chat_session_id: session&.id,
            chat_started_at: session&.started_at&.iso8601,
            chat_messages: ticket.replies.public_replies.chronological.includes(:author).map { |r| chat_message_json(r) },
            chat_metadata: session&.metadata
          )
        end

        base
      end

      def chat_message_json(reply)
        {
          id: reply.id,
          body: reply.body,
          is_internal_note: false,
          is_agent: reply.author.respond_to?(:escalated_agent?) ? reply.author.escalated_agent? : false,
          author: if reply.author
                    { id: reply.author.id,
                      name: reply.author.respond_to?(:name) ? reply.author.name : reply.author.email }
                  else
                    { name: 'System' }
                  end,
          created_at: reply.created_at&.iso8601
        }
      end

      def reply_json(reply)
        {
          id: reply.id,
          body: reply.body,
          author: {
            name: reply.author.respond_to?(:name) ? reply.author.name : reply.author&.email,
            is_agent: reply.author.respond_to?(:escalated_agent?) ? reply.author.escalated_agent? : false
          },
          attachments: reply.attachments.map do |a|
            { id: a.id, filename: a.filename, size: a.human_size, url: Services::AttachmentService.url_for(a) }
          end,
          created_at: reply.created_at&.iso8601,
          is_system: reply.is_system
        }
      end

      def customer_ticket_path(ticket)
        escalated.customer_ticket_path(ticket)
      end

      def new_customer_ticket_path
        escalated.new_customer_ticket_path
      end
    end
  end
end
