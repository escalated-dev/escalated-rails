# frozen_string_literal: true

module Escalated
  class AgentChannel < ApplicationCable::Channel
    def subscribed
      if authorized_agent?
        [Escalated::Broadcasting.agent_channel,
         Escalated::Broadcasting.agent_channel(current_user.id)].each do |channel|
          stream_from channel, coder: ActiveSupport::JSON do |message|
            authorized_agent? ? transmit(message) : stop_all_streams
          end
        end
      else
        reject
      end
    end

    def unsubscribed
      stop_all_streams
    end

    private

    def authorized_agent?
      return false unless current_user
      return false if TicketAccess.restricted?(current_user)

      (current_user.respond_to?(:escalated_agent?) && current_user.escalated_agent?) ||
        (current_user.respond_to?(:escalated_admin?) && current_user.escalated_admin?)
    end
  end
end
