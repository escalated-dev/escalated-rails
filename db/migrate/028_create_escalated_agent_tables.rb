class CreateEscalatedAgentTables < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("agent_profiles") do |t|
      t.bigint :user_id, null: false
      t.string :agent_type, default: "full", null: false
      t.integer :max_tickets

      t.timestamps
    end

    add_index Escalated.table_name("agent_profiles"), :user_id, unique: true

    create_table Escalated.table_name("skills") do |t|
      t.string :name, null: false
      t.string :slug, null: false

      t.timestamps
    end

    add_index Escalated.table_name("skills"), :slug, unique: true

    create_table Escalated.table_name("agent_skills"), id: false do |t|
      t.bigint :user_id, null: false
      t.bigint :skill_id, null: false
      t.integer :proficiency, default: 1, null: false
    end

    add_index Escalated.table_name("agent_skills"),
              [:user_id, :skill_id],
              unique: true,
              name: "idx_escalated_agent_skills_unique"

    create_table Escalated.table_name("agent_capacity") do |t|
      t.bigint :user_id, null: false
      t.string :channel, default: "default", null: false
      t.integer :max_concurrent, default: 10, null: false
      t.integer :current_count, default: 0, null: false

      t.timestamps
    end

    add_index Escalated.table_name("agent_capacity"),
              [:user_id, :channel],
              unique: true,
              name: "idx_escalated_agent_capacity_unique"
  end
end
