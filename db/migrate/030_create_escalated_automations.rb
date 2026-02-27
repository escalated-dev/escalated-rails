class CreateEscalatedAutomations < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("automations") do |t|
      t.string :name, null: false
      t.json :conditions
      t.json :actions
      t.boolean :active, default: true, null: false
      t.integer :position, default: 0, null: false
      t.datetime :last_run_at

      t.timestamps
    end

    add_index Escalated.table_name("automations"), :active
    add_index Escalated.table_name("automations"), :position
  end
end
