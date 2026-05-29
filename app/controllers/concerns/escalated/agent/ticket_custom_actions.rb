# frozen_string_literal: true

module Escalated
  module Agent
    # Agent-side handling for host-defined custom ticket actions: triggering an
    # action (which dispatches the `custom_action_triggered` notification) and
    # serializing the visible actions for the ticket show screen.
    module TicketCustomActions
      extend ActiveSupport::Concern

      included do
        before_action :set_ticket, only: %i[custom_action]
      end

      def custom_action
        authorize @ticket, policy_class: Escalated::TicketPolicy

        registry = Escalated.ticket_action_registry
        user = escalated_current_user
        action = registry.find(params[:action_key])

        raise ActiveRecord::RecordNotFound if action.nil? || !registry.visible?(action, @ticket, user)
        return head(:forbidden) unless registry.enabled?(action, @ticket, user)

        Services::NotificationService.dispatch(
          :custom_action_triggered,
          ticket: @ticket,
          action_key: action[:key].to_s,
          user: user,
          payload: custom_action_payload,
          metadata: registry.metadata(action, @ticket, user)
        )

        redirect_to agent_ticket_path(@ticket), notice: 'Custom action dispatched.'
      end

      private

      # Serialize the visible custom actions for a ticket, adding url + method.
      def custom_actions_for(ticket)
        Escalated.ticket_action_registry.for_ticket(ticket, escalated_current_user).map do |action|
          action.merge(
            url: escalated.custom_action_agent_ticket_path(ticket, action[:key]),
            method: 'post'
          )
        end
      end

      def custom_action_payload
        raw = params[:payload]
        return {} if raw.blank?

        raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
      end
    end
  end
end
