class CreateEscalatedRolesAndPermissions < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("permissions") do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :group
      t.text :description

      t.timestamps
    end

    add_index Escalated.table_name("permissions"), :slug, unique: true
    add_index Escalated.table_name("permissions"), :group

    create_table Escalated.table_name("roles") do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.boolean :is_system, default: false, null: false

      t.timestamps
    end

    add_index Escalated.table_name("roles"), :slug, unique: true

    create_table Escalated.table_name("role_permissions"), id: false do |t|
      t.bigint :role_id, null: false
      t.bigint :permission_id, null: false
    end

    add_index Escalated.table_name("role_permissions"),
              [:role_id, :permission_id],
              unique: true,
              name: "idx_escalated_role_permissions_unique"

    create_table Escalated.table_name("role_users"), id: false do |t|
      t.bigint :role_id, null: false
      t.bigint :user_id, null: false
    end

    add_index Escalated.table_name("role_users"),
              [:role_id, :user_id],
              unique: true,
              name: "idx_escalated_role_users_unique"
  end
end
