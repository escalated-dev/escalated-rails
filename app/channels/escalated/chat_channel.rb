# frozen_string_literal: true

module Escalated
  class ChatChannel < ApplicationCable::Channel
    def subscribed
      ticket = Escalated::Ticket.find(params[:ticket_id])

      if authorized_for_chat?(ticket)
        stream_from Escalated::Broadcasting.chat_channel(ticket), coder: ActiveSupport::JSON do |message|
          current_ticket = Escalated::Ticket.find_by(id: ticket.id)
          if current_ticket && authorized_for_chat?(current_ticket)
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

    def authorized_for_chat?(ticket)
      return false unless TicketAccess.chat_allowed?(current_user, ticket, params[:session])
      return true unless current_user

      # Agents and admins can subscribe
      return true if current_user.respond_to?(:escalated_agent?) && current_user.escalated_agent?
      return true if current_user.respond_to?(:escalated_admin?) && current_user.escalated_admin?

      # Requesters can subscribe to their own chat
      ticket.requester == current_user
    end
  end
end
