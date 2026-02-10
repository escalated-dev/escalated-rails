module Escalated
  module Guest
    class TicketsController < ActionController::Base
      protect_from_forgery with: :exception

      before_action :ensure_guest_tickets_enabled
      before_action :set_ticket_by_token, only: [:show, :reply, :rate]
      before_action :set_inertia_shared_data

      def create
        render inertia: "Escalated/Guest/Create", props: {
          departments: Escalated::Department.active.ordered.map { |d|
            { id: d.id, name: d.name }
          },
          priorities: Escalated::Ticket.priorities.keys,
          default_priority: Escalated.configuration.default_priority.to_s
        }
      end

      def store
        errors = validate_guest_params
        if errors.any?
          render inertia: "Escalated/Guest/Create", props: {
            errors: errors,
            old: guest_ticket_params.to_h,
            departments: Escalated::Department.active.ordered.map { |d|
              { id: d.id, name: d.name }
            },
            priorities: Escalated::Ticket.priorities.keys,
            default_priority: Escalated.configuration.default_priority.to_s
          }
          return
        end

        guest_token = SecureRandom.hex(32) # 64-character hex string

        ticket = Escalated::Ticket.create!(
          requester: nil,
          guest_name: guest_ticket_params[:name],
          guest_email: guest_ticket_params[:email],
          guest_token: guest_token,
          subject: guest_ticket_params[:subject],
          description: guest_ticket_params[:description],
          priority: guest_ticket_params[:priority] || Escalated.configuration.default_priority,
          department_id: guest_ticket_params[:department_id].presence
        )

        if guest_ticket_params[:attachments].present?
          Services::AttachmentService.attach(ticket, guest_ticket_params[:attachments])
        end

        redirect_to "#{escalated_mount_path}/guest/#{guest_token}", notice: "Ticket created successfully."
      rescue Services::AttachmentService::TooManyAttachmentsError,
             Services::AttachmentService::FileTooLargeError,
             Services::AttachmentService::InvalidFileTypeError => e
        redirect_back fallback_location: "#{escalated_mount_path}/guest/create", alert: e.message
      end

      def show
        replies = @ticket.replies
          .where(is_internal: false, is_system: false)
          .order(created_at: :asc)
          .includes(:author, :attachments)

        render inertia: "Escalated/Guest/Show", props: {
          ticket: guest_ticket_json(@ticket),
          replies: replies.map { |r| guest_reply_json(r) },
          token: params[:token],
          can_reply: @ticket.open?
        }
      end

      def reply
        unless @ticket.open?
          redirect_to "#{escalated_mount_path}/guest/#{params[:token]}", alert: "This ticket is closed."
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
        if @ticket.waiting_on_customer?
          @ticket.update!(status: :open)
        end

        if params[:attachments].present?
          Services::AttachmentService.attach(reply, params[:attachments])
        end

        redirect_to "#{escalated_mount_path}/guest/#{params[:token]}", notice: "Reply sent."
      rescue Services::AttachmentService::TooManyAttachmentsError,
             Services::AttachmentService::FileTooLargeError,
             Services::AttachmentService::InvalidFileTypeError => e
        redirect_to "#{escalated_mount_path}/guest/#{params[:token]}", alert: e.message
      end

      def rate
        unless %w[resolved closed].include?(@ticket.status)
          redirect_to "#{escalated_mount_path}/guest/#{params[:token]}",
                      alert: "You can only rate resolved or closed tickets."
          return
        end

        if @ticket.satisfaction_rating.present?
          redirect_to "#{escalated_mount_path}/guest/#{params[:token]}",
                      alert: "This ticket has already been rated."
          return
        end

        rating = Escalated::SatisfactionRating.new(
          ticket: @ticket,
          rating: params[:rating].to_i,
          comment: params[:comment]
        )

        if rating.save
          redirect_to "#{escalated_mount_path}/guest/#{params[:token]}",
                      notice: "Thank you for your feedback!"
        else
          redirect_to "#{escalated_mount_path}/guest/#{params[:token]}",
                      alert: rating.errors.full_messages.join(", ")
        end
      end

      private

      def ensure_guest_tickets_enabled
        unless Escalated::EscalatedSetting.guest_tickets_enabled?
          render plain: "Guest tickets are not enabled.", status: :not_found
        end
      end

      def set_ticket_by_token
        @ticket = Escalated::Ticket.find_by!(guest_token: params[:token])
      rescue ActiveRecord::RecordNotFound
        render plain: "Ticket not found.", status: :not_found
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
        params.permit(:name, :email, :subject, :description, :priority, :department_id, attachments: [])
      end

      def validate_guest_params
        errors = {}
        errors[:name] = "Name is required." if guest_ticket_params[:name].blank?
        errors[:email] = "Email is required." if guest_ticket_params[:email].blank?
        errors[:subject] = "Subject is required." if guest_ticket_params[:subject].blank?
        errors[:description] = "Description is required." if guest_ticket_params[:description].blank?
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
          department: ticket.department ? { id: ticket.department.id, name: ticket.department.name } : nil,
          created_at: ticket.created_at&.iso8601,
          updated_at: ticket.updated_at&.iso8601,
          satisfaction_rating: ticket.satisfaction_rating ? {
            id: ticket.satisfaction_rating.id,
            rating: ticket.satisfaction_rating.rating,
            comment: ticket.satisfaction_rating.comment,
            created_at: ticket.satisfaction_rating.created_at&.iso8601
          } : nil
        }
      end

      def guest_reply_json(reply)
        author_name = if reply.author
                        reply.author.respond_to?(:name) ? reply.author.name : reply.author&.email
                      else
                        @ticket.guest_name || "Guest"
                      end

        {
          id: reply.id,
          body: reply.body,
          author: {
            name: author_name,
            is_agent: reply.author.respond_to?(:escalated_agent?) ? reply.author.escalated_agent? : false
          },
          attachments: reply.attachments.map { |a|
            { id: a.id, filename: a.filename, size: a.human_size }
          },
          created_at: reply.created_at&.iso8601,
          is_system: reply.is_system
        }
      end
    end
  end
end
