# frozen_string_literal: true

class CreateEscalatedSkillRoutingTags < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name('skill_routing_tags') do |t|
      t.references :skill, null: false, foreign_key: { to_table: Escalated.table_name('skills'), on_delete: :cascade }
      t.references :tag, null: false, foreign_key: { to_table: Escalated.table_name('tags'), on_delete: :cascade }

      t.timestamps
    end

    add_index Escalated.table_name('skill_routing_tags'),
              %i[skill_id tag_id],
              unique: true,
              name: 'idx_escalated_skill_routing_tags_skill_tag'
  end
end
