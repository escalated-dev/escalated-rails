class AddIsPinnedToEscalatedReplies < ActiveRecord::Migration[7.0]
  def change
    add_column Escalated.table_name("replies"), :is_pinned, :boolean, default: false, null: false
    add_index Escalated.table_name("replies"), :is_pinned
  end
end
