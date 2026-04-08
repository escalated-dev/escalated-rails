# frozen_string_literal: true

class AddSnoozeFieldsToEscalatedTickets < ActiveRecord::Migration[7.1]
  def change
    add_column Escalated.table_name('tickets'), :snoozed_until, :datetime, null: true
    add_column Escalated.table_name('tickets'), :snoozed_by, :bigint, null: true
    add_column Escalated.table_name('tickets'), :status_before_snooze, :integer, null: true

    add_index Escalated.table_name('tickets'), :snoozed_until
  end
end
