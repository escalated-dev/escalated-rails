module Escalated
  module Customer
    class TicketsController < Escalated::ApplicationController
      before_action :set_ticket, only: [:show, :reply, :close, :reopen]

      def index
        scope = Escalated::Ticket.where(
          requester: escalated_current_user
        ).recent

        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.search(params[:search]) if params[:search].present?

        result = paginate(scope)

        render inertia: "Escalated/Customer/Index", props: {
          tickets: result[:data].map { |t| ticket_json(t) },
          meta: result[:meta],
          filters: {
            status: params[:status],
            search: params[:search]
          }
        }
      end

      def create
        render inertia: "Escalated/Customer/Create", props: {
          departments: Escalated::Department.active.ordered.map { |d|
            { id: d.id, name: d.name }
          },
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

        if ticket_params[:attachments].present?
          Services::AttachmentService.attach(ticket, ticket_params[:attachments])
        end

        redirect_to customer_ticket_path(ticket), notice: I18n.t('escalated.ticket.created')
      rescue Services::AttachmentService::TooManyAttachmentsError,
             Services::AttachmentService::FileTooLargeError,
             Services::AttachmentService::InvalidFileTypeError => e
        redirect_back fallback_location: new_customer_ticket_path, alert: e.message
      end

      def show
        authorize @ticket, policy_class: Escalated::TicketPolicy

        replies = @ticket.replies
          .public_replies
          .chronological
          .includes(:author, :attachments)

        render inertia: "Escalated/Customer/Show", props: {
          ticket: ticket_json(@ticket),
          replies: replies.map { |r| reply_json(r) },
          can_close: Escalated.configuration.allow_customer_close && @ticket.open?,
          can_reopen: %w[resolved closed].include?(@ticket.status)
        }
      end

      def reply
        authorize @ticket, policy_class: Escalated::TicketPolicy

        reply = Services::TicketService.reply(@ticket, {
          body: params[:body],
          author: escalated_current_user,
          is_internal: false
        })

        if params[:attachments].present?
          Services::AttachmentService.attach(reply, params[:attachments])
        end

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
        params.require(:ticket).permit(:subject, :description, :priority, :department_id, attachments: [])
      end

      def ticket_json(ticket)
        {
          id: ticket.id,
          reference: ticket.reference,
          subject: ticket.subject,
          description: ticket.description,
          status: ticket.status,
          priority: ticket.priority,
          department: ticket.department ? { id: ticket.department.id, name: ticket.department.name } : nil,
          created_at: ticket.created_at&.iso8601,
          updated_at: ticket.updated_at&.iso8601,
          resolved_at: ticket.resolved_at&.iso8601,
          reply_count: ticket.replies.public_replies.count,
          satisfaction_rating: ticket.satisfaction_rating ? {
            id: ticket.satisfaction_rating.id,
            rating: ticket.satisfaction_rating.rating,
            comment: ticket.satisfaction_rating.comment,
            created_at: ticket.satisfaction_rating.created_at&.iso8601
          } : nil
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
          attachments: reply.attachments.map { |a|
            { id: a.id, filename: a.filename, size: a.human_size, url: Services::AttachmentService.url_for(a) }
          },
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
