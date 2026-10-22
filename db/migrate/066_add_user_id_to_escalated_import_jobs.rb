# frozen_string_literal: true

# The admin who started an import, as escalated-laravel records it.
class AddUserIdToEscalatedImportJobs < ActiveRecord::Migration[7.0]
  def change
    add_column Escalated.table_name('import_jobs'), :user_id, Escalated.user_id_type
    add_index Escalated.table_name('import_jobs'), :user_id
  end
end
