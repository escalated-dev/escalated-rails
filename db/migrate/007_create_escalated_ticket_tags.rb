class CreateEscalatedTicketTags < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("ticket_tags"), id: false do |t|
      t.references :ticket, null: false, foreign_key: { to_table: Escalated.table_name("tickets") }
      t.references :tag, null: false, foreign_key: { to_table: Escalated.table_name("tags") }
    end

    add_index Escalated.table_name("ticket_tags"),
              [:ticket_id, :tag_id],
              unique: true,
              name: "idx_escalated_ticket_tags_unique"
  end
end
