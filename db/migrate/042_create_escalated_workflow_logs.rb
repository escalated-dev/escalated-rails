# frozen_string_literal: true

class CreateEscalatedWorkflowLogs < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name('workflow_logs') do |t|
      t.references :workflow, null: false, foreign_key: { to_table: Escalated.table_name('workflows') }
      t.references :ticket, null: false, foreign_key: { to_table: Escalated.table_name('tickets') }
      t.string :trigger_event, null: false
      t.string :status, null: false, default: 'success'
      t.json :actions_executed
      t.text :error_message

      t.timestamps
    end
  end
end
