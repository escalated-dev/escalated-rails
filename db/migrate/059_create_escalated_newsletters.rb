# frozen_string_literal: true

class CreateEscalatedNewsletters < ActiveRecord::Migration[7.0]
  def change
    table_name = "#{Escalated.configuration.table_prefix}newsletters"
    lists_table = "#{Escalated.configuration.table_prefix}newsletter_lists"
    templates_table = "#{Escalated.configuration.table_prefix}newsletter_templates"

    create_table table_name do |t|
      t.string :subject, null: false, limit: 998
      t.string :from_email, null: false, limit: 320
      t.string :from_name
      t.string :reply_to, limit: 320
      t.bigint :target_list_id, null: false
      t.bigint :template_id
      t.string :theme, limit: 64
      t.text :body_markdown
      t.string :status, null: false, limit: 16, default: 'draft'
      t.datetime :scheduled_at
      t.datetime :sent_at
      t.column :created_by, Escalated.user_id_type
      t.column :sent_by, Escalated.user_id_type
      t.integer :summary_total, default: 0
      t.integer :summary_sent, default: 0
      t.integer :summary_opened, default: 0
      t.integer :summary_clicked, default: 0
      t.integer :summary_bounced, default: 0
      t.integer :summary_complained, default: 0
      t.timestamps
    end

    add_index table_name, :status
    add_index table_name, :scheduled_at
    add_index table_name, %i[status scheduled_at]
    add_index table_name, :created_by
    add_foreign_key table_name, lists_table, column: :target_list_id, on_delete: :restrict
    add_foreign_key table_name, templates_table, column: :template_id, on_delete: :nullify
  end
end
