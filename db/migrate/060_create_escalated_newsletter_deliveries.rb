# frozen_string_literal: true

class CreateEscalatedNewsletterDeliveries < ActiveRecord::Migration[7.0]
  def change
    table_name = "#{Escalated.configuration.table_prefix}newsletter_deliveries"
    newsletters_table = "#{Escalated.configuration.table_prefix}newsletters"
    contacts_table = "#{Escalated.configuration.table_prefix}contacts"

    create_table table_name do |t|
      t.bigint :newsletter_id, null: false
      t.bigint :contact_id, null: false
      t.string :email_at_send, null: false, limit: 320
      t.string :status, null: false, limit: 16, default: 'pending'
      t.string :tracking_token, null: false, limit: 40
      t.datetime :sent_at
      t.datetime :opened_at
      t.datetime :last_clicked_at
      t.integer :clicks_count, default: 0
      t.text :bounce_reason
      t.text :failure_reason
      t.integer :attempt_count, default: 0, limit: 2
      t.datetime :claimed_at
      t.boolean :is_test, default: false
      t.datetime :created_at, null: false
    end

    add_index table_name, :tracking_token, unique: true
    # Explicit short names — auto-generated composite-index names exceed the
    # 64-char limit on this (long) table name.
    add_index table_name, %i[newsletter_id status], name: 'idx_esc_nl_deliveries_newsletter_status'
    add_index table_name, :contact_id
    add_index table_name, %i[status claimed_at], name: 'idx_esc_nl_deliveries_status_claimed'
    add_foreign_key table_name, newsletters_table, column: :newsletter_id, on_delete: :cascade
    add_foreign_key table_name, contacts_table, column: :contact_id, on_delete: :cascade
  end
end
