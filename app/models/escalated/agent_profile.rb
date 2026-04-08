# frozen_string_literal: true

module Escalated
  class AgentProfile < ApplicationRecord
    self.table_name = Escalated.table_name('agent_profiles')

    belongs_to :user, class_name: Escalated.configuration.user_class

    CHAT_STATUSES = %w[online away offline].freeze

    validates :user_id, uniqueness: true
    validates :chat_status, inclusion: { in: CHAT_STATUSES }, allow_nil: true

    scope :chat_online, -> { where(chat_status: 'online') }
    scope :chat_available, -> { where(chat_status: %w[online away]) }

    def chat_online?
      chat_status == 'online'
    end

    def chat_away?
      chat_status == 'away'
    end

    def chat_offline?
      chat_status == 'offline'
    end

    def light_agent?
      agent_type == 'light'
    end

    def full_agent?
      agent_type == 'full'
    end

    def self.for_user(user_id)
      find_by(user_id: user_id)
    end
  end
end
