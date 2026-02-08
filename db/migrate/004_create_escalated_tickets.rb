class CreateEscalatedTickets < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("tickets") do |t|
      t.string :reference, null: false
      t.string :subject, null: false
      t.text :description, null: false
      t.integer :status, default: 0, null: false
      t.integer :priority, default: 1, null: false

      # Polymorphic requester
      t.string :requester_type, null: false
      t.bigint :requester_id, null: false

      # Assignee (agent user)
      t.bigint :assigned_to

      # Department
      t.references :department, foreign_key: { to_table: Escalated.table_name("departments") }, null: true

      # SLA
      t.references :sla_policy, foreign_key: { to_table: Escalated.table_name("sla_policies") }, null: true
      t.datetime :sla_first_response_due_at
      t.datetime :sla_resolution_due_at
      t.boolean :sla_breached, default: false, null: false

      # Timestamps
      t.datetime :first_response_at
      t.datetime :resolved_at
      t.datetime :closed_at

      # Metadata
      t.json :metadata, default: {}

      t.timestamps
    end

    add_index Escalated.table_name("tickets"), :reference, unique: true
    add_index Escalated.table_name("tickets"), :status
    add_index Escalated.table_name("tickets"), :priority
    add_index Escalated.table_name("tickets"), [:requester_type, :requester_id]
    add_index Escalated.table_name("tickets"), :assigned_to
    add_index Escalated.table_name("tickets"), :sla_breached
    add_index Escalated.table_name("tickets"), :sla_first_response_due_at
    add_index Escalated.table_name("tickets"), :sla_resolution_due_at
    add_index Escalated.table_name("tickets"), :created_at
    add_index Escalated.table_name("tickets"), :resolved_at
  end
end
