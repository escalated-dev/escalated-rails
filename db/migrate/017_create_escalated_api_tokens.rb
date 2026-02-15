class CreateEscalatedApiTokens < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("api_tokens") do |t|
      # Polymorphic tokenable (the user who owns this token)
      t.string :tokenable_type, null: false
      t.bigint :tokenable_id, null: false

      t.string :name, null: false
      t.string :token, limit: 64, null: false
      t.json :abilities, default: ["*"]
      t.datetime :last_used_at
      t.string :last_used_ip, limit: 45
      t.datetime :expires_at

      t.timestamps
    end

    add_index Escalated.table_name("api_tokens"), :token, unique: true
    add_index Escalated.table_name("api_tokens"), [:tokenable_type, :tokenable_id]
    add_index Escalated.table_name("api_tokens"), :expires_at
  end
end
