# frozen_string_literal: true

class AddRoleFlagsToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :is_admin, :boolean, default: false, null: false
    add_column :users, :is_agent, :boolean, default: false, null: false
  end
end
