class CreateEscalatedCustomFields < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("custom_fields") do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :field_type, null: false
      t.string :context, null: false, default: "ticket"
      t.json :options
      t.boolean :required, default: false, null: false
      t.string :placeholder
      t.text :description
      t.json :validation_rules
      t.json :conditions
      t.integer :position, default: 0, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index Escalated.table_name("custom_fields"), :slug, unique: true
    add_index Escalated.table_name("custom_fields"), :context
    add_index Escalated.table_name("custom_fields"), :active
    add_index Escalated.table_name("custom_fields"), :position

    create_table Escalated.table_name("custom_field_values") do |t|
      t.bigint :custom_field_id, null: false
      t.string :entity_type, null: false
      t.bigint :entity_id, null: false
      t.text :value

      t.timestamps
    end

    add_index Escalated.table_name("custom_field_values"), :custom_field_id
    add_index Escalated.table_name("custom_field_values"),
              [:entity_type, :entity_id],
              name: "idx_escalated_custom_field_values_entity"
    add_foreign_key Escalated.table_name("custom_field_values"),
                    Escalated.table_name("custom_fields"),
                    column: :custom_field_id
  end
end
