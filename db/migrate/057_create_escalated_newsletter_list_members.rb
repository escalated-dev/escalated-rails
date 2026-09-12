# frozen_string_literal: true

class CreateEscalatedNewsletterListMembers < ActiveRecord::Migration[7.0]
  def change
    table_name = "#{Escalated.configuration.table_prefix}newsletter_list_members"
    lists_table = "#{Escalated.configuration.table_prefix}newsletter_lists"
    contacts_table = "#{Escalated.configuration.table_prefix}contacts"

    create_table table_name do |t|
      t.bigint :list_id, null: false
      t.bigint :contact_id, null: false
      # No database default. Rails creates this as datetime(6) on MySQL, where a
      # default of CURRENT_TIMESTAMP does not match that precision and the
      # column is rejected outright ("Invalid default value for 'added_at'") --
      # so the engine could not be installed there. Escalated::NewsletterListMember
      # sets it, which every adapter treats identically.
      t.datetime :added_at, null: false
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
