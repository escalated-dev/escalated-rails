# frozen_string_literal: true

module Escalated
  class ChatSession < ApplicationRecord
    self.table_name = Escalated.table_name('chat_sessions')

    belongs_to :ticket, class_name: 'Escalated::Ticket'
    belongs_to :agent, class_name: Escalated.configuration.user_class, optional: true

    validates :customer_session_id, presence: true
    validates :status, presence: true, inclusion: { in: %w[waiting active ended transferred] }
    validates :rating, inclusion: { in: 1..5 }, allow_nil: true

    scope :waiting, -> { where(status: 'waiting') }
    scope :active, -> { where(status: 'active') }
    scope :ended, -> { where(status: 'ended') }
    scope :for_agent, ->(agent_id) { where(agent_id: agent_id) }
    scope :recent, -> { order(created_at: :desc) }

    def waiting?
      status == 'waiting'
    end

    def active?
      status == 'active'
    end

    def ended?
      status == 'ended'
    end

    def duration
      return nil unless started_at

      (ended_at || Time.current) - started_at
    end
  end
end
