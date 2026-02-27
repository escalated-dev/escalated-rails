class CreateEscalatedCustomObjects < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("custom_objects") do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.json :fields_schema

      t.timestamps
    end

    add_index Escalated.table_name("custom_objects"), :slug, unique: true

    create_table Escalated.table_name("custom_object_records") do |t|
      t.bigint :object_id, null: false
      t.json :data

      t.timestamps
    end

    add_index Escalated.table_name("custom_object_records"), :object_id
    add_foreign_key Escalated.table_name("custom_object_records"),
                    Escalated.table_name("custom_objects"),
                    column: :object_id,
                    on_delete: :cascade
  end
end
