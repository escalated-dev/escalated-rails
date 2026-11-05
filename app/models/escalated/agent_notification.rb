# frozen_string_literal: true

module Escalated
  # An in-app notification for an agent (ADR 2026-11-05-agent-panel-data,
  # section 4). `data` holds the ticket id and reference; the ticket is not a
  # column, so a ticket the agent can no longer see redacts the item rather
  # than hiding it.
  class AgentNotification < ApplicationRecord
    self.table_name = Escalated.table_name('notifications')
    # `type` is the feed type, not a Rails STI class name.
    self.inheritance_column = nil

    attribute :data, default: -> { {} }

    scope :unread, -> { where(read_at: nil) }
    scope :for_user, ->(user_id) { where(user_id: user_id) }
  end
end
