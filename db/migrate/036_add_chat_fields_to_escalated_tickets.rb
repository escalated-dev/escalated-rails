# frozen_string_literal: true

class AddChatFieldsToEscalatedTickets < ActiveRecord::Migration[7.1]
  def change
    add_column Escalated.table_name('tickets'), :channel, :string, default: 'email', null: false
    add_column Escalated.table_name('tickets'), :chat_ended_at, :datetime, null: true
    add_column Escalated.table_name('tickets'), :chat_metadata, :json, null: true

    add_index Escalated.table_name('tickets'), :channel
  end
end
