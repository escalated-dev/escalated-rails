# frozen_string_literal: true

class CreateEscalatedMentions < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name('mentions') do |t|
      t.references :reply, null: false, foreign_key: { to_table: Escalated.table_name('replies') }
      t.bigint :user_id, null: false
      t.datetime :read_at

      t.timestamps
    end

    add_index Escalated.table_name('mentions'), :user_id
    add_index Escalated.table_name('mentions'), %i[reply_id user_id], unique: true
  end
end
