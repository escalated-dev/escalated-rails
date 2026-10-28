# frozen_string_literal: true

# Widget chat tokens expire, as in escalated-laravel. Chats already in progress
# keep a null expiry; the next request with their token stores its hash and
# gives it a full lifetime (Escalated::ChatSession.for_visitor_token).
class AddCustomerTokenExpiresAtToEscalatedChatSessions < ActiveRecord::Migration[7.0]
  def change
    add_column Escalated.table_name('chat_sessions'), :customer_token_expires_at, :datetime
  end
end
