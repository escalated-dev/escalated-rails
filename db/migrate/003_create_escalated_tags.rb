class CreateEscalatedTags < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("tags") do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :color
      t.text :description

      t.timestamps
    end

    add_index Escalated.table_name("tags"), :name, unique: true
    add_index Escalated.table_name("tags"), :slug, unique: true
  end
end
