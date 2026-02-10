class CreateEscalatedMacros < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("macros") do |t|
      t.string :name, null: false
      t.string :description
      t.json :actions, null: false
      t.bigint :created_by
      t.boolean :is_shared, default: true, null: false
      t.integer :order, default: 0, null: false

      t.timestamps
    end

    add_index Escalated.table_name("macros"), :created_by
    add_index Escalated.table_name("macros"), :is_shared
    add_index Escalated.table_name("macros"), :order
  end
end
