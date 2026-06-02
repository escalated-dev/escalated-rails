# frozen_string_literal: true

class CreateEscalatedNewsletterLists < ActiveRecord::Migration[7.0]
  def change
    table_name = "#{Escalated.configuration.table_prefix}newsletter_lists"

    create_table table_name do |t|
      t.string :name, null: false
      t.text :description
      t.string :kind, null: false, limit: 16
      t.json :filter_json
      t.column :created_by, Escalated.user_id_type
      t.timestamps
    end

    add_index table_name, :kind
    add_index table_name, :created_by
  end
end
