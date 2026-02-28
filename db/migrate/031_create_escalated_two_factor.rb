class CreateEscalatedTwoFactor < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("two_factors") do |t|
      t.bigint :user_id, null: false
      t.text :secret
      t.json :recovery_codes
      t.datetime :confirmed_at

      t.timestamps
    end

    add_index Escalated.table_name("two_factors"), :user_id, unique: true
  end
end
