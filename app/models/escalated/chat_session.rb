# frozen_string_literal: true

module Escalated
  class ChatSession < ApplicationRecord
    self.table_name = Escalated.table_name('chat_sessions')

    default_scope { Escalated::TicketAccess.children(self) }

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

    # The visitor's chat token, handed back once when the chat starts. Only its
    # SHA-256 is stored, in customer_session_id.
    attr_accessor :visitor_token

    # As in escalated-laravel, a widget chat token is an expiring grant: it
    # stops working guest_access_ttl_minutes after the chat starts.
    def self.digest(token)
      Digest::SHA256.hexdigest(token.to_s)
    end

    # A new [token, digest, expires_at].
    def self.issue_visitor_token
      token = SecureRandom.hex(16)
      [token, digest(token), Escalated::GuestAccess.ttl.from_now]
    end

    # The chat the visitor's unexpired token unlocks, or nil. Chats started
    # before tokens were hashed hold the plain token and no expiry: the first
    # request with one stores its hash and gives it a full lifetime, so chats
    # in progress during an upgrade keep working.
    def self.for_visitor_token(token, scope = all)
      token = token.to_s
      return nil if token.empty? || token.length > 255

      session = scope.find_by(customer_session_id: digest(token)) ||
                scope.find_by(customer_session_id: token, customer_token_expires_at: nil)
      return nil unless session

      if session.customer_token_expires_at.nil?
        session.update_columns(customer_session_id: digest(token),
                               customer_token_expires_at: Escalated::GuestAccess.ttl.from_now)
      end
      session.customer_token_expires_at > Time.current ? session : nil
    end

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
