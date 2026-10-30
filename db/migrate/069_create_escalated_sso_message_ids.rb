# frozen_string_literal: true

# Single-use SSO message IDs (ADR 2026-10-29-configurable-access-features):
# SAML requests Escalated issued, and SAML assertion IDs and JWT jtis it
# accepted. expires_at is Unix seconds.
class CreateEscalatedSsoMessageIds < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name('sso_message_ids') do |t|
      t.string :kind, limit: 32, null: false
      t.string :message_id, limit: 191, null: false
      t.bigint :expires_at, null: false
    end

    add_index Escalated.table_name('sso_message_ids'), %i[kind message_id], unique: true,
                                                                            name: 'idx_escalated_sso_message_ids_unique'
    add_index Escalated.table_name('sso_message_ids'), :expires_at, name: 'idx_escalated_sso_message_ids_expires'
  end
end
