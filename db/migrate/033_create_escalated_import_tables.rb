class CreateEscalatedImportTables < ActiveRecord::Migration[7.0]
  # MySQL has no uuid type at all, so `id: :uuid` was not a portable choice --
  # the engine could not be installed on MySQL, and the failure was a raw SQL
  # syntax error rather than anything that named the cause.
  #
  # PostgreSQL keeps its native type, because an existing install already has
  # it and it is the better column where it exists. Everywhere else the id is a
  # 36-character string, which holds the same value; Escalated::ImportJob
  # generates it, so no database-side default is needed either way.
  def uuid_type
    connection.adapter_name == 'PostgreSQL' ? :uuid : :string
  end

  def change
    # ------------------------------------------------------------------
    # import_jobs
    # ------------------------------------------------------------------
    create_table Escalated.table_name("import_jobs"), id: uuid_type, default: nil do |t|
      t.string  :platform,      null: false
      t.string  :status,        null: false, default: "pending"

      # Encrypted credentials blob (Rails 7 ActiveRecord Encryption stores as text)
      t.text    :credentials

      # JSON columns
      # No database default: MySQL forbids one on a JSON column, which made the
      # engine impossible to install there. The model carries it instead.
      t.json    :field_mappings
      t.json    :progress
      t.json    :error_log

      # Timestamps
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index Escalated.table_name("import_jobs"), :platform
    add_index Escalated.table_name("import_jobs"), :status

    # ------------------------------------------------------------------
    # import_source_maps
    # ------------------------------------------------------------------
    create_table Escalated.table_name("import_source_maps") do |t|
      t.references :import_job,
                   type:       uuid_type,
                   null:       false,
                   foreign_key: { to_table: Escalated.table_name("import_jobs") },
                   index:      false

      t.string :entity_type,  null: false
      t.string :source_id,    null: false
      t.string :escalated_id, null: false

      # created_at only — this is an append-only mapping table
      t.datetime :created_at, null: false
    end

    add_index Escalated.table_name("import_source_maps"),
              [:import_job_id, :entity_type, :source_id],
              unique: true,
              name:   "idx_escalated_import_source_maps_unique"

    add_index Escalated.table_name("import_source_maps"),
              [:import_job_id, :entity_type, :escalated_id],
              name: "idx_escalated_import_source_maps_lookup"
  end
end
