# frozen_string_literal: true

# department_agents.agent_id (008) and chat_sessions.agent_id (037) were created
# as bigint, while every other host-user column follows Escalated.user_id_type.
# On a host with UUID or string user keys, adding an agent to a department,
# department visibility, department auto-assign and chat assignment all failed.
#
# A no-op on bigint hosts. On other hosts no valid row can exist yet (a UUID
# never fit in these columns), so the existing values are cast as text.
class ChangeEscalatedAgentColumnsToUserIdType < ActiveRecord::Migration[7.0]
  # table, column, null
  COLUMNS = [['department_agents', 'agent_id', false], ['chat_sessions', 'agent_id', true]].freeze

  def up
    type = Escalated.user_id_type
    return if type.to_s == 'bigint'

    COLUMNS.each do |table, column, null|
      change_user_column(Escalated.table_name(table), column, type, null)
    end
  end

  def down
    COLUMNS.each do |table, column, null|
      table_name = Escalated.table_name(table)
      next if connection.columns(table_name).find { |c| c.name == column }&.type == :integer

      change_user_column(table_name, column, :bigint, null)
    end
  end

  private

  # `null` is passed every time: MySQL's MODIFY COLUMN drops NOT NULL otherwise.
  def change_user_column(table_name, column, type, null)
    options = { null: null }
    if connection.adapter_name.downcase.include?('postgres')
      options[:using] = type.to_s == 'bigint' ? "NULLIF(#{column}::text, '')::bigint" : "#{column}::text::#{type}"
    end
    change_column table_name, column, type, **options
  end
end
