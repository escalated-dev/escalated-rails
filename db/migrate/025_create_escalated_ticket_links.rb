class CreateEscalatedTicketLinks < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("ticket_links") do |t|
      t.bigint :parent_ticket_id, null: false
      t.bigint :child_ticket_id, null: false
      t.string :link_type, null: false

      t.timestamps
    end

    add_index Escalated.table_name("ticket_links"),
              [:parent_ticket_id, :child_ticket_id, :link_type],
              unique: true,
              name: "idx_escalated_ticket_links_unique"
    add_index Escalated.table_name("ticket_links"), :parent_ticket_id
    add_index Escalated.table_name("ticket_links"), :child_ticket_id
  end
end
