# frozen_string_literal: true

class CreateEscalatedSavedViews < ActiveRecord::Migration[7.1]
  def change
    create_table Escalated.table_name('saved_views') do |t|
      t.string :name, null: false
      t.json :filters, default: {}
      t.bigint :user_id, null: true
      t.boolean :is_shared, default: false, null: false
      t.boolean :is_default, default: false, null: false
      t.integer :position, default: 0, null: false
      t.string :icon
      t.string :color

      t.timestamps
    end

    add_index Escalated.table_name('saved_views'), :user_id
    add_index Escalated.table_name('saved_views'), :is_shared
    add_index Escalated.table_name('saved_views'), :position
  end
end
