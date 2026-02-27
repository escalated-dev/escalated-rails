class CreateEscalatedTicketStatuses < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("ticket_statuses") do |t|
      t.string :label, null: false
      t.string :slug, null: false
      t.string :category
      t.string :color, default: "#6b7280"
      t.text :description
      t.integer :position, default: 0, null: false
      t.boolean :is_default, default: false, null: false

      t.timestamps
    end

    add_index Escalated.table_name("ticket_statuses"), :slug, unique: true
    add_index Escalated.table_name("ticket_statuses"), :category
    add_index Escalated.table_name("ticket_statuses"), :position
  end
end
