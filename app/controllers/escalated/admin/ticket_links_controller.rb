module Escalated
  module Admin
    class TicketLinksController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_ticket

      def index
        links = @ticket.ticket_links.includes(:linked_ticket)

        render json: links.map { |l| link_json(l) }
      end

      def store
        linked_ticket = Escalated::Ticket.find_by(id: params[:linked_ticket_id])

        return render json: { error: "Ticket not found" }, status: :not_found unless linked_ticket
        return render json: { error: "Cannot link a ticket to itself" }, status: :unprocessable_entity if linked_ticket.id == @ticket.id

        existing = Escalated::TicketLink.where(ticket_id: @ticket.id, linked_ticket_id: linked_ticket.id)
          .or(Escalated::TicketLink.where(ticket_id: linked_ticket.id, linked_ticket_id: @ticket.id))
          .exists?

        return render json: { error: "Link already exists" }, status: :unprocessable_entity if existing

        link = Escalated::TicketLink.create!(
          ticket: @ticket,
          linked_ticket: linked_ticket,
          link_type: params[:link_type] || "related"
        )

        render json: link_json(link), status: :created
      end

      def destroy
        link = @ticket.ticket_links.find(params[:link_id])
        link.destroy!

        render json: { success: true }
      end

      private

      def set_ticket
        @ticket = Escalated::Ticket.find(params[:ticket_id])
      end

      def link_json(link)
        {
          id: link.id,
          link_type: link.link_type,
          linked_ticket: {
            id: link.linked_ticket.id,
            reference: link.linked_ticket.reference,
            subject: link.linked_ticket.subject,
            status: link.linked_ticket.status,
            priority: link.linked_ticket.priority
          },
          created_at: link.created_at&.iso8601
        }
      end
    end
  end
end
