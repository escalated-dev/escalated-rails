# frozen_string_literal: true

module Escalated
  # The agent's own Online / Away / Offline status (ADR
  # 2026-11-05-agent-panel-data, section 3), stored in the agent profile's
  # chat_status, the field live-chat routing reads, so there is one status per
  # agent whichever route set it. An agent with no profile is offline.
  module AgentStatus
    module_function

    def values
      Escalated::AgentProfile::CHAT_STATUSES
    end

    def for(user)
      Escalated::AgentProfile.find_by(user_id: user.id)&.chat_status || 'offline'
    end

    def set(user, status)
      profile = Escalated::AgentProfile.find_or_create_by!(user_id: user.id) { |p| p.agent_type = 'full' }
      profile.update!(chat_status: status)
    end
  end
end
