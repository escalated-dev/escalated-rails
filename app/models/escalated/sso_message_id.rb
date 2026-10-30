# frozen_string_literal: true

module Escalated
  # Single-use SSO message IDs: issued requests to be answered once
  # (remember / consume), and accepted IDs that must not come again (claim).
  # Expired rows are pruned on write.
  class SsoMessageId < ApplicationRecord
    self.table_name = Escalated.table_name('sso_message_ids')

    MAX_LENGTH = 191

    def self.remember(kind, message_id, expires_at)
      prune
      create!(kind: kind, message_id: message_id, expires_at: expires_at)
    end

    # Removes an unexpired remembered ID: true only the first time.
    def self.consume(kind, message_id)
      return false if message_id.blank? || message_id.length > MAX_LENGTH

      where(kind: kind, message_id: message_id).where('expires_at > ?', Time.now.to_i).delete_all == 1
    end

    # Records an ID as used: true the first time, false on a replay.
    def self.claim(kind, message_id, expires_at)
      return false if message_id.blank? || message_id.length > MAX_LENGTH

      prune
      create!(kind: kind, message_id: message_id, expires_at: expires_at)
      true
    rescue ActiveRecord::RecordNotUnique
      false
    end

    def self.prune
      where(expires_at: ..Time.now.to_i).delete_all
    end
  end
end
