# frozen_string_literal: true

class CreateEscalatedChatSessions < ActiveRecord::Migration[7.1]
  def change
    create_table Escalated.table_name('chat_sessions') do |t|
      t.bigint :ticket_id, null: false
      t.string :customer_session_id, null: false
      t.bigint :agent_id, null: true
      t.string :status, default: 'waiting', null: false
      t.datetime :started_at, null: true
      t.datetime :ended_at, null: true
      t.datetime :customer_typing_at, null: true
      t.datetime :agent_typing_at, null: true
      t.json :metadata, null: true
      t.integer :rating, null: true
      t.text :rating_comment, null: true

      t.timestamps
    end

    add_index Escalated.table_name('chat_sessions'), :ticket_id
    add_index Escalated.table_name('chat_sessions'), :customer_session_id
    add_index Escalated.table_name('chat_sessions'), :agent_id
    add_index Escalated.table_name('chat_sessions'), :status
  end
end
