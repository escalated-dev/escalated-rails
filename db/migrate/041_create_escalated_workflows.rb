# frozen_string_literal: true

class CreateEscalatedWorkflows < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name('workflows') do |t|
      t.string :name, null: false
      t.string :trigger_event, null: false
      t.json :conditions
      t.json :actions
      t.boolean :is_active, default: true, null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index Escalated.table_name('workflows'), :trigger_event
    add_index Escalated.table_name('workflows'), :is_active
    add_index Escalated.table_name('workflows'), :position
  end
end
