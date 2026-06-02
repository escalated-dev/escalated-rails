# frozen_string_literal: true

class AddNextAttemptAtToEscalatedNewsletterDeliveries < ActiveRecord::Migration[7.0]
  def change
    table_name = "#{Escalated.configuration.table_prefix}newsletter_deliveries"

    add_column table_name, :next_attempt_at, :datetime
    add_index table_name, :next_attempt_at
  end
end
