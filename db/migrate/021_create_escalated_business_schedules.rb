class CreateEscalatedBusinessSchedules < ActiveRecord::Migration[7.0]
  def change
    create_table Escalated.table_name("business_schedules") do |t|
      t.string :name, null: false
      t.string :timezone, null: false, default: "UTC"
      t.boolean :is_default, default: false, null: false
      t.json :schedule

      t.timestamps
    end

    add_index Escalated.table_name("business_schedules"), :is_default

    create_table Escalated.table_name("holidays") do |t|
      t.bigint :schedule_id, null: false
      t.string :name, null: false
      t.date :date, null: false
      t.boolean :recurring, default: false, null: false

      t.timestamps
    end

    add_index Escalated.table_name("holidays"), :schedule_id
    add_index Escalated.table_name("holidays"), :date
    add_foreign_key Escalated.table_name("holidays"),
                    Escalated.table_name("business_schedules"),
                    column: :schedule_id
  end
end
