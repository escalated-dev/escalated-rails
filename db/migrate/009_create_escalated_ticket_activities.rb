class CreateEscalatedTicketActivities < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("ticket_activities") do |t|
      t.references :ticket, null: false, foreign_key: { to_table: Escalated.table_name("tickets") }
      t.string :action, null: false

      # Polymorphic causer (user or system)
      t.string :causer_type
      t.column :causer_id, Escalated.user_id_type

      # No database default: MySQL forbids one on a JSON column, which made the
      # engine impossible to install there. The model carries it instead.
      t.json :details

      t.timestamps
    end

    add_index Escalated.table_name("ticket_activities"),
              [:causer_type, :causer_id],
              name: "idx_escalated_ticket_activities_causer"
    add_index Escalated.table_name("ticket_activities"), :action
    add_index Escalated.table_name("ticket_activities"), :created_at
  end
end
