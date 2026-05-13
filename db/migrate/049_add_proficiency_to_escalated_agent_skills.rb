# frozen_string_literal: true

class AddProficiencyToEscalatedAgentSkills < ActiveRecord::Migration[7.0]
  def change
    skills_table = Escalated.table_name('skills')
    agent_skills_table = Escalated.table_name('agent_skills')

    add_column skills_table, :description, :text unless column_exists?(skills_table, :description)

    unless column_exists?(agent_skills_table, :created_at)
      add_column agent_skills_table, :created_at, :datetime
      add_column agent_skills_table, :updated_at, :datetime
    end

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE #{agent_skills_table}
          SET created_at = CURRENT_TIMESTAMP,
              updated_at = CURRENT_TIMESTAMP
          WHERE created_at IS NULL OR updated_at IS NULL
        SQL
      end
    end

    change_column_null agent_skills_table, :created_at, false
    change_column_null agent_skills_table, :updated_at, false

    change_column_default agent_skills_table, :proficiency, 3

    add_check_constraint agent_skills_table,
                         'proficiency >= 1 AND proficiency <= 5',
                         name: 'chk_escalated_agent_skills_proficiency'
  end
end
