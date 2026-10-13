# frozen_string_literal: true

module Escalated
  class TicketChannel < ApplicationCable::Channel
    def subscribed
      ticket = Escalated::Ticket.find(params[:ticket_id])

      # Only agents/admins can subscribe to ticket channels
      if authorized_for_ticket?(ticket)
        stream_from Escalated::Broadcasting.ticket_channel(ticket), coder: ActiveSupport::JSON do |message|
          current_ticket = Escalated::Ticket.find_by(id: ticket.id)
          if current_ticket && authorized_for_ticket?(current_ticket)
            transmit(message)
          else
            stop_all_streams
          end
        end
      else
        reject
      end
    rescue ActiveRecord::RecordNotFound
      reject
    end

    def unsubscribed
      stop_all_streams
    end

    private

    def authorized_for_ticket?(ticket)
      return false unless current_user
      return false unless TicketAccess.allowed?(current_user, ticket)

      # Agents and admins can subscribe
      return true if current_user.respond_to?(:escalated_agent?) && current_user.escalated_agent?

      return true if current_user.respond_to?(:escalated_admin?) && current_user.escalated_admin?

      # Requesters can subscribe to their own tickets
      ticket.requester == current_user
    end
  end
end
