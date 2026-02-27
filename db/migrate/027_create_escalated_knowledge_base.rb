class CreateEscalatedKnowledgeBase < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("article_categories") do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.bigint :parent_id
      t.integer :position, default: 0, null: false
      t.text :description

      t.timestamps
    end

    add_index Escalated.table_name("article_categories"), :slug, unique: true
    add_index Escalated.table_name("article_categories"), :parent_id
    add_index Escalated.table_name("article_categories"), :position

    create_table Escalated.table_name("articles") do |t|
      t.bigint :category_id
      t.string :title, null: false
      t.string :slug, null: false
      t.text :body
      t.string :status, default: "draft", null: false
      t.bigint :author_id
      t.integer :view_count, default: 0, null: false
      t.integer :helpful_count, default: 0, null: false
      t.integer :not_helpful_count, default: 0, null: false
      t.datetime :published_at

      t.timestamps
    end

    add_index Escalated.table_name("articles"), :slug, unique: true
    add_index Escalated.table_name("articles"), :category_id
    add_index Escalated.table_name("articles"), :status
    add_index Escalated.table_name("articles"), :author_id
    add_index Escalated.table_name("articles"), :published_at
  end
end
