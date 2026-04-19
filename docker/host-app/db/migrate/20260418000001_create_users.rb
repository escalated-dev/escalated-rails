class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.boolean :is_admin, default: false, null: false
      t.boolean :is_agent, default: false, null: false
      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end
