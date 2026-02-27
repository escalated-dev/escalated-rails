class AddTypeAndMergedIntoToTickets < ActiveRecord::Migration[7.0]
  def change
    add_column Escalated.table_name("tickets"), :ticket_type, :string, default: "question"
    add_column Escalated.table_name("tickets"), :merged_into_id, :bigint, null: true

    add_index Escalated.table_name("tickets"), :ticket_type
    add_index Escalated.table_name("tickets"), :merged_into_id
  end
end
