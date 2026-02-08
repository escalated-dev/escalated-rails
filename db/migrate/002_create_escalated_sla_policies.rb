class CreateEscalatedSlaPolicies < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("sla_policies") do |t|
      t.string :name, null: false
      t.text :description
      t.json :first_response_hours, null: false
      t.json :resolution_hours, null: false
      t.boolean :is_active, default: true, null: false
      t.boolean :is_default, default: false, null: false

      t.timestamps
    end

    add_index Escalated.table_name("sla_policies"), :name, unique: true
    add_index Escalated.table_name("sla_policies"), :is_active
    add_index Escalated.table_name("sla_policies"), :is_default

    add_foreign_key Escalated.table_name("departments"),
                    Escalated.table_name("sla_policies"),
                    column: :default_sla_policy_id,
                    on_delete: :nullify
  end
end
