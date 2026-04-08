# frozen_string_literal: true

module Escalated
  class AgentChannel < ApplicationCable::Channel
    def subscribed
      if authorized_agent?
        stream_from Escalated::Broadcasting.agent_channel
        stream_from Escalated::Broadcasting.agent_channel(current_user.id)
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

      (current_user.respond_to?(:escalated_agent?) && current_user.escalated_agent?) ||
        (current_user.respond_to?(:escalated_admin?) && current_user.escalated_admin?)
    end
  end
end
