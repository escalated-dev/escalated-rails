class CreateEscalatedAuditLogs < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("audit_logs") do |t|
      t.bigint :user_id, null: true
      t.string :action, null: false
      t.string :auditable_type
      t.bigint :auditable_id
      t.json :old_values
      t.json :new_values
      t.string :ip_address
      t.string :user_agent, limit: 500

      t.timestamps
    end

    add_index Escalated.table_name("audit_logs"), [:auditable_type, :auditable_id]
    add_index Escalated.table_name("audit_logs"), :user_id
    add_index Escalated.table_name("audit_logs"), :action
    add_index Escalated.table_name("audit_logs"), :created_at
  end
end
