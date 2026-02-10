class CreateEscalatedTicketFollowers < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("ticket_followers"), id: false do |t|
      t.bigint :ticket_id, null: false
      t.bigint :user_id, null: false

      t.timestamps
    end

    add_index Escalated.table_name("ticket_followers"),
              [:ticket_id, :user_id],
              unique: true,
              name: "idx_escalated_ticket_followers_unique"
    add_foreign_key Escalated.table_name("ticket_followers"),
                    Escalated.table_name("tickets"),
                    column: :ticket_id
  end
end
