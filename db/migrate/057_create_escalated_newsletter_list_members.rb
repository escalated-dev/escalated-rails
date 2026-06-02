# frozen_string_literal: true

class CreateEscalatedNewsletterListMembers < ActiveRecord::Migration[7.0]
  def change
    table_name = "#{Escalated.configuration.table_prefix}newsletter_list_members"
    lists_table = "#{Escalated.configuration.table_prefix}newsletter_lists"
    contacts_table = "#{Escalated.configuration.table_prefix}contacts"

    create_table table_name do |t|
      t.bigint :list_id, null: false
      t.bigint :contact_id, null: false
      t.datetime :added_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.column :added_by, Escalated.user_id_type
    end

    # Explicit short name — the auto-generated name exceeds the 64-char index
    # name limit once the table prefix is applied.
    add_index table_name, %i[list_id contact_id], unique: true, name: 'idx_esc_nl_list_members_uniq'
    add_index table_name, :contact_id, name: 'idx_esc_nl_list_members_contact'
    add_foreign_key table_name, lists_table, column: :list_id, on_delete: :cascade
    add_foreign_key table_name, contacts_table, column: :contact_id, on_delete: :cascade
  end
end
