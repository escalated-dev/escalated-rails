class CreateEscalatedInboundEmails < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("inbound_emails") do |t|
      t.string :message_id
      t.string :from_email, null: false
      t.string :from_name
      t.string :to_email, null: false
      t.string :subject, null: false
      t.text :body_text
      t.text :body_html
      t.text :raw_headers

      t.references :ticket, foreign_key: { to_table: Escalated.table_name("tickets") }, null: true
      t.references :reply, foreign_key: { to_table: Escalated.table_name("replies") }, null: true

      t.string :status, default: "pending", null: false
      t.string :adapter, null: false
      t.text :error_message

      t.datetime :processed_at

      t.timestamps
    end

    add_index Escalated.table_name("inbound_emails"), :message_id, unique: true
    add_index Escalated.table_name("inbound_emails"), :from_email
    add_index Escalated.table_name("inbound_emails"), :status
    add_index Escalated.table_name("inbound_emails"), :processed_at
  end
end
