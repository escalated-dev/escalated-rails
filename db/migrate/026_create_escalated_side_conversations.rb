class CreateEscalatedSideConversations < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("side_conversations") do |t|
      t.bigint :ticket_id, null: false
      t.string :subject, null: false
      t.string :channel, default: "email"
      t.string :status, default: "open", null: false
      t.bigint :created_by_id

      t.timestamps
    end

    add_index Escalated.table_name("side_conversations"), :ticket_id
    add_index Escalated.table_name("side_conversations"), :status
    add_foreign_key Escalated.table_name("side_conversations"),
                    Escalated.table_name("tickets"),
                    column: :ticket_id

    create_table Escalated.table_name("side_conversation_replies") do |t|
      t.bigint :side_conversation_id, null: false
      t.text :body, null: false
      t.bigint :author_id

      t.timestamps
    end

    add_index Escalated.table_name("side_conversation_replies"), :side_conversation_id,
              name: "idx_esc_side_conv_replies_on_conv_id"
    add_foreign_key Escalated.table_name("side_conversation_replies"),
                    Escalated.table_name("side_conversations"),
                    column: :side_conversation_id
  end
end
