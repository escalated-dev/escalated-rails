class CreateEscalatedSatisfactionRatings < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("satisfaction_ratings") do |t|
      t.references :ticket, null: false, foreign_key: { to_table: Escalated.table_name("tickets") }
      t.integer :rating, null: false
      t.text :comment

      # Polymorphic rated_by (nullable for guest ratings)
      t.string :rated_by_type
      t.bigint :rated_by_id

      t.datetime :created_at
    end

    add_index Escalated.table_name("satisfaction_ratings"), [:rated_by_type, :rated_by_id]
    add_index Escalated.table_name("satisfaction_ratings"),
              :ticket_id,
              unique: true,
              name: "idx_escalated_satisfaction_ratings_ticket"
  end
end
