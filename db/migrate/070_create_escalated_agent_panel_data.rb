# frozen_string_literal: true

# The agent panel's data (ADR 2026-11-05-agent-panel-data):
#
# - tickets.last_customer_activity_at and ticket_reads: per-agent unread
#   markers. Existing tickets get no activity, so none turn unread on upgrade.
# - customer_presence: when each customer was last seen by the portal or widget.
# - notifications: the agents' in-app notifications.
#
# The agent's own status uses the existing agent_profiles.chat_status.
class CreateEscalatedAgentPanelData < ActiveRecord::Migration[7.0]
  def change
    tickets = Escalated.table_name('tickets')
    add_column tickets, :last_customer_activity_at, :datetime
    add_index tickets, :last_customer_activity_at, name: 'esc_tickets_customer_activity'

    create_table Escalated.table_name('ticket_reads') do |t|
      t.column :user_id, Escalated.user_id_type, null: false
      t.references :ticket, null: false, index: false,
                            foreign_key: { to_table: tickets, on_delete: :cascade }
      t.datetime :last_read_at
      t.timestamps
    end
    add_index Escalated.table_name('ticket_reads'), %i[user_id ticket_id], unique: true,
                                                                           name: 'esc_ticket_reads_unique'
    add_index Escalated.table_name('ticket_reads'), :ticket_id, name: 'esc_ticket_reads_ticket'

    create_table Escalated.table_name('customer_presence') do |t|
      t.string :subject_type, limit: 191, null: false
      # A string, so it holds integer, UUID and string keys alike.
      t.string :subject_id, limit: 64, null: false
      t.datetime :last_seen_at, null: false
      t.timestamps
    end
    add_index Escalated.table_name('customer_presence'), %i[subject_type subject_id], unique: true,
                                                                                      name: 'esc_presence_unique'

    create_table Escalated.table_name('notifications'), id: false do |t|
      t.string :id, limit: 36, null: false, primary_key: true
      t.column :user_id, Escalated.user_id_type, null: false
      t.string :type, limit: 64, null: false
      t.json :data
      t.datetime :read_at
      t.datetime :created_at, null: false
    end
    add_index Escalated.table_name('notifications'), %i[user_id read_at], name: 'esc_notifications_user'
  end
end
