class CreateEscalatedTicketActivities < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("ticket_activities") do |t|
      t.references :ticket, null: false, foreign_key: { to_table: Escalated.table_name("tickets") }
      t.string :action, null: false

      # Polymorphic causer (user or system)
      t.string :causer_type
      t.bigint :causer_id

      t.json :details, default: {}

      t.timestamps
    end

    add_index Escalated.table_name("ticket_activities"), [:causer_type, :causer_id]
    add_index Escalated.table_name("ticket_activities"), :action
    add_index Escalated.table_name("ticket_activities"), :created_at
  end
end
