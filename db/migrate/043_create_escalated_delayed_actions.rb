# frozen_string_literal: true

class CreateEscalatedDelayedActions < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name('delayed_actions') do |t|
      t.references :workflow, null: false, foreign_key: { to_table: Escalated.table_name('workflows') }
      t.references :ticket, null: false, foreign_key: { to_table: Escalated.table_name('tickets') }
      t.json :action_data, null: false
      t.datetime :execute_at, null: false
      t.boolean :executed, default: false, null: false

      t.timestamps
    end

    add_index Escalated.table_name('delayed_actions'), :execute_at
    add_index Escalated.table_name('delayed_actions'), :executed
  end
end
