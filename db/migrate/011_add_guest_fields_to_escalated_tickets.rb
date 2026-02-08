class AddGuestFieldsToEscalatedTickets < ActiveRecord::Migration[7.0]
  def up
    table_name = "#{Escalated.configuration.table_prefix}tickets"

    # Make requester polymorphic fields nullable for guest tickets
    change_column_null table_name, :requester_type, true
    change_column_null table_name, :requester_id, true

    # Add guest ticket fields
    add_column table_name, :guest_name, :string, null: true
    add_column table_name, :guest_email, :string, null: true
    add_column table_name, :guest_token, :string, limit: 64, null: true

    add_index table_name, :guest_token, unique: true
  end

  def down
    table_name = "#{Escalated.configuration.table_prefix}tickets"

    remove_column table_name, :guest_name
    remove_column table_name, :guest_email
    remove_index table_name, :guest_token
    remove_column table_name, :guest_token

    change_column_null table_name, :requester_type, false
    change_column_null table_name, :requester_id, false
  end
end
