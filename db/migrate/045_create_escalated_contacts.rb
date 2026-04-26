# frozen_string_literal: true

# Adds a first-class Contact entity for guest requesters, mirroring the
# escalated-nestjs Contact design (Pattern B). Enables email-level dedupe
# across tickets and a clean "promote to user" flow.
#
# Keeps the inline guest_name/guest_email/guest_token columns on tickets
# for backwards compatibility (Pattern A). A follow-up backfill migration
# populates contact_id for existing tickets; the dual-read period lets
# callers transition without a flag day.
class CreateEscalatedContacts < ActiveRecord::Migration[7.0]
  def up
    contacts_table = "#{Escalated.configuration.table_prefix}contacts"
    tickets_table = "#{Escalated.configuration.table_prefix}tickets"

    create_table contacts_table do |t|
      t.string :email, null: false, limit: 320
      t.string :name, null: true
      t.bigint :user_id, null: true,
                         comment: 'Linked host-app user id once the contact creates an account'
      t.json :metadata, default: {}
      t.timestamps
    end

    add_index contacts_table, :email, unique: true
    add_index contacts_table, :user_id

    add_column tickets_table, :contact_id, :bigint, null: true
    add_foreign_key tickets_table, contacts_table, column: :contact_id, on_delete: :nullify
    add_index tickets_table, :contact_id
  end

  def down
    contacts_table = "#{Escalated.configuration.table_prefix}contacts"
    tickets_table = "#{Escalated.configuration.table_prefix}tickets"

    remove_foreign_key tickets_table, column: :contact_id
    remove_index tickets_table, :contact_id
    remove_column tickets_table, :contact_id
    drop_table contacts_table
  end
end
