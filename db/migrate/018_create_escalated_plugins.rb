class CreateEscalatedPlugins < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("plugins") do |t|
      t.string   :slug,             null: false
      t.boolean  :is_active,        null: false, default: false
      t.datetime :activated_at
      t.datetime :deactivated_at

      t.timestamps
    end

    add_index Escalated.table_name("plugins"), :slug, unique: true
    add_index Escalated.table_name("plugins"), :is_active
  end
end
