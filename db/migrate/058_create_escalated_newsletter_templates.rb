# frozen_string_literal: true

class CreateEscalatedNewsletterTemplates < ActiveRecord::Migration[7.0]
  def change
    table_name = "#{Escalated.configuration.table_prefix}newsletter_templates"

    create_table table_name do |t|
      t.string :name, null: false
      t.string :theme, null: false, default: 'default', limit: 64
      t.string :subject_template, limit: 998
      t.text :body_markdown, null: false
      t.json :merge_fields_schema
      t.column :created_by, Escalated.user_id_type
      t.timestamps
    end

    add_index table_name, :theme
    add_index table_name, :created_by
  end
end
