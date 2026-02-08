class CreateEscalatedSettings < ActiveRecord::Migration[7.0]
  def up
    table_name = "#{Escalated.configuration.table_prefix}settings"

    create_table table_name do |t|
      t.string :key, null: false
      t.text :value
      t.timestamps
    end

    add_index table_name, :key, unique: true

    # Seed default settings
    now = Time.current
    execute <<-SQL.squish
      INSERT INTO #{table_name} (#{connection.quote_column_name('key')}, value, created_at, updated_at)
      VALUES
        ('guest_tickets_enabled', '1', '#{now.utc.iso8601}', '#{now.utc.iso8601}'),
        ('allow_customer_close', '1', '#{now.utc.iso8601}', '#{now.utc.iso8601}'),
        ('auto_close_resolved_after_days', '7', '#{now.utc.iso8601}', '#{now.utc.iso8601}'),
        ('max_attachments_per_reply', '5', '#{now.utc.iso8601}', '#{now.utc.iso8601}'),
        ('max_attachment_size_kb', '10240', '#{now.utc.iso8601}', '#{now.utc.iso8601}')
    SQL
  end

  def down
    drop_table "#{Escalated.configuration.table_prefix}settings"
  end
end
