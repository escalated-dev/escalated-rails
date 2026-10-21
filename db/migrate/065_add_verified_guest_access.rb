# frozen_string_literal: true

# Verified guest access (escalated-laravel docs/guest-access.md): one-time
# email codes, and expiring grants that store only a hash of their nonce.
class AddVerifiedGuestAccess < ActiveRecord::Migration[7.0]
  def change
    tickets = Escalated.table_name('tickets')
    add_column tickets, :guest_access_hash, :string, limit: 64
    add_column tickets, :guest_access_expires_at, :datetime
    add_column tickets, :guest_verified_email, :string
    add_column tickets, :guest_email_verified_at, :datetime

    # The address is kept only as a keyed digest: a code is checked against
    # the mailbox that asked for it, and nothing here can be read back.
    create_table Escalated.table_name('guest_verifications'), id: false do |t|
      t.string :id, limit: 36, null: false, primary_key: true
      t.string :email_digest, limit: 64, null: false
      t.string :purpose, limit: 16, null: false
      t.string :code_hash, limit: 64, null: false
      t.integer :attempts, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.timestamps
    end
    add_index Escalated.table_name('guest_verifications'), :expires_at, name: 'esc_guest_verifications_expires'
  end
end
