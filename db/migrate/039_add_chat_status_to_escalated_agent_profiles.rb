# frozen_string_literal: true

class AddChatStatusToEscalatedAgentProfiles < ActiveRecord::Migration[7.1]
  def change
    add_column Escalated.table_name('agent_profiles'), :chat_status, :string, default: 'offline', null: false
  end
end
