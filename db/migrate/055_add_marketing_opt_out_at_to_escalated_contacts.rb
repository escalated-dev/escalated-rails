# frozen_string_literal: true

class AddMarketingOptOutAtToEscalatedContacts < ActiveRecord::Migration[7.0]
  def change
    contacts_table = "#{Escalated.configuration.table_prefix}contacts"
    add_column contacts_table, :marketing_opt_out_at, :datetime, null: true
    add_index contacts_table, :marketing_opt_out_at
  end
end
