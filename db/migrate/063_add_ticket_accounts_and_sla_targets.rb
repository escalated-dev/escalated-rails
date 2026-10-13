# frozen_string_literal: true

class AddTicketAccountsAndSlaTargets < ActiveRecord::Migration[7.0]
  def change
    tickets = Escalated.table_name('tickets')
    policies = Escalated.table_name('sla_policies')
    adapter = connection.adapter_name.downcase
    collation = if adapter.include?('mysql')
                  'utf8mb4_bin'
                elsif adapter.include?('postgres')
                  'C'
                else
                  'BINARY'
                end
    add_column tickets, :account_type, :string, collation: collation
    add_column tickets, :account_id, :string, collation: collation
    add_index tickets, %i[account_type account_id], name: 'esc_tickets_account'
    add_reference policies, :department, foreign_key: { to_table: Escalated.table_name('departments') }
    add_column policies, :ticket_type, :string
    add_index policies, :ticket_type
  end
end
