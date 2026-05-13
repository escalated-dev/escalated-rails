# frozen_string_literal: true

class CreateEscalatedSkillRoutingDepartments < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name('skill_routing_departments') do |t|
      t.references :skill, null: false, foreign_key: { to_table: Escalated.table_name('skills'), on_delete: :cascade }
      t.references :department, null: false, foreign_key: { to_table: Escalated.table_name('departments'), on_delete: :cascade }

      t.timestamps
    end

    add_index Escalated.table_name('skill_routing_departments'),
              %i[skill_id department_id],
              unique: true,
              name: 'idx_escalated_skill_routing_departments_skill_dept'
  end
end
