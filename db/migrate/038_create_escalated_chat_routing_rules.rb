# frozen_string_literal: true

class CreateEscalatedChatRoutingRules < ActiveRecord::Migration[7.1]
  def change
    create_table Escalated.table_name('chat_routing_rules') do |t|
      t.bigint :department_id, null: true
      t.string :routing_strategy, default: 'round_robin', null: false
      t.string :offline_behavior, default: 'show_form', null: false
      t.integer :max_queue_size, default: 50, null: false
      t.integer :max_concurrent_per_agent, default: 5, null: false
      t.integer :auto_close_after_minutes, default: 30, null: false
      t.text :queue_message, null: true
      t.text :offline_message, null: true
      t.boolean :is_active, default: true, null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index Escalated.table_name('chat_routing_rules'), :department_id
    add_index Escalated.table_name('chat_routing_rules'), :is_active
  end
end
