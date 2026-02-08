class CreateEscalatedSupportTables < ActiveRecord::Migration[7.0]
  def change
    # Department-Agent join table
    create_table Escalated.table_name("department_agents"), id: false do |t|
      t.bigint :department_id, null: false
      t.bigint :agent_id, null: false
    end

    add_index Escalated.table_name("department_agents"),
              [:department_id, :agent_id],
              unique: true,
              name: "idx_escalated_dept_agents_unique"
    add_foreign_key Escalated.table_name("department_agents"),
                    Escalated.table_name("departments"),
                    column: :department_id

    # Escalation Rules
    create_table Escalated.table_name("escalation_rules") do |t|
      t.string :name, null: false
      t.text :description
      t.json :conditions, null: false
      t.json :actions, null: false
      t.integer :priority, default: 0, null: false
      t.boolean :is_active, default: true, null: false

      t.timestamps
    end

    add_index Escalated.table_name("escalation_rules"), :is_active
    add_index Escalated.table_name("escalation_rules"), :priority

    # Canned Responses
    create_table Escalated.table_name("canned_responses") do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.string :shortcode
      t.string :category
      t.boolean :is_shared, default: false, null: false
      t.bigint :created_by, null: false

      t.timestamps
    end

    add_index Escalated.table_name("canned_responses"), :shortcode, unique: true
    add_index Escalated.table_name("canned_responses"), :is_shared
    add_index Escalated.table_name("canned_responses"), :created_by
    add_index Escalated.table_name("canned_responses"), :category
  end
end
