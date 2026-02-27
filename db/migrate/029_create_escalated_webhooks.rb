class CreateEscalatedWebhooks < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("webhooks") do |t|
      t.string :url, null: false
      t.json :events
      t.string :secret
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index Escalated.table_name("webhooks"), :active

    create_table Escalated.table_name("webhook_deliveries") do |t|
      t.bigint :webhook_id, null: false
      t.string :event, null: false
      t.json :payload
      t.integer :response_code
      t.text :response_body
      t.integer :attempts, default: 0, null: false
      t.datetime :delivered_at

      t.timestamps
    end

    add_index Escalated.table_name("webhook_deliveries"), :webhook_id
    add_index Escalated.table_name("webhook_deliveries"), :event
    add_index Escalated.table_name("webhook_deliveries"), :delivered_at
    add_foreign_key Escalated.table_name("webhook_deliveries"),
                    Escalated.table_name("webhooks"),
                    column: :webhook_id,
                    on_delete: :cascade
  end
end
