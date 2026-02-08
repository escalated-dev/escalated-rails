class CreateEscalatedDepartments < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("departments") do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :email
      t.boolean :is_active, default: true, null: false
      t.bigint :default_sla_policy_id

      t.timestamps
    end

    add_index Escalated.table_name("departments"), :slug, unique: true
    add_index Escalated.table_name("departments"), :is_active
    add_index Escalated.table_name("departments"), :name, unique: true
  end
end
