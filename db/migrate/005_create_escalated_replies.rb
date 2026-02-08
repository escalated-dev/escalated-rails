class CreateEscalatedReplies < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("replies") do |t|
      t.references :ticket, null: false, foreign_key: { to_table: Escalated.table_name("tickets") }
      t.text :body, null: false

      # Polymorphic author
      t.string :author_type
      t.bigint :author_id

      t.boolean :is_internal, default: false, null: false
      t.boolean :is_system, default: false, null: false

      t.timestamps
    end

    add_index Escalated.table_name("replies"), [:author_type, :author_id]
    add_index Escalated.table_name("replies"), :is_internal
    add_index Escalated.table_name("replies"), :created_at
  end
end
