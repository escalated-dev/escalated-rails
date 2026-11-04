# frozen_string_literal: true

module Escalated
  module Agent
    # What the agent ticket page needs beyond the ticket itself: snoozing from
    # the agent panel (the admin panel's snooze, authorized as a ticket update)
    # and the requester's other tickets for the customer panel.
    module TicketWorkspace
      extend ActiveSupport::Concern

      # The ticket loads in the action, after the controller's agent check, so a
      # hidden one answers 404 only to staff who pass it.
      def snooze
        set_ticket
        authorize @ticket, :update?, policy_class: Escalated::TicketPolicy

        until_time = snooze_until
        unless until_time
          message = I18n.t('escalated.ticket.snooze_invalid_time', default: 'Choose a snooze time in the future.')
          return redirect_back_or_to(agent_ticket_path(@ticket), alert: message,
                                                                 inertia: { errors: { 'snoozed_until' => message } })
        end

        Services::TicketService.snooze_ticket(@ticket, until_time, actor: escalated_current_user)
        redirect_to agent_ticket_path(@ticket), notice: I18n.t('escalated.ticket.snoozed')
      end

      def unsnooze
        set_ticket
        authorize @ticket, :update?, policy_class: Escalated::TicketPolicy

        Services::TicketService.unsnooze_ticket(@ticket)
        redirect_to agent_ticket_path(@ticket), notice: I18n.t('escalated.ticket.unsnoozed')
      end

      private

      # snoozed_until as a time strictly in the future, or nil when it is
      # missing, not a date, or not in the future.
      def snooze_until
        value = params[:snoozed_until]
        return nil unless value.is_a?(String) && value.present?

        time = Time.zone.parse(value)
        time if time&.future?
      rescue ArgumentError
        nil
      end

      # The requester's five most recent other tickets the agent may see (the
      # visibility scope applies), matched as requester_ticket_count is: the
      # registered requester, or a guest's email.
      def requester_tickets_json(ticket)
        scope = Escalated::Ticket.where.not(id: ticket.id)
        if ticket.requester_type.present? && ticket.requester_id.present?
          scope = scope.where(requester_type: ticket.requester_type, requester_id: ticket.requester_id)
        elsif ticket.guest? && ticket.guest_email.present?
          scope = scope.where(guest_email: ticket.guest_email)
        else
          return []
        end

        scope.reorder(created_at: :desc, id: :desc).limit(5).map do |other|
          {
            id: other.id,
            reference: other.reference,
            subject: other.subject,
            status: other.status.to_s,
            created_at: other.created_at&.iso8601,
            updated_at: other.updated_at&.iso8601
          }
        end
      end
    end
  end
end
