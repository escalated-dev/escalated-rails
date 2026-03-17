class CreateEscalatedImportTables < ActiveRecord::Migration[7.0]
  def change
    # ------------------------------------------------------------------
    # import_jobs
    # ------------------------------------------------------------------
    create_table Escalated.table_name("import_jobs"), id: :uuid do |t|
      t.string  :platform,      null: false
      t.string  :status,        null: false, default: "pending"

      # Encrypted credentials blob (Rails 7 ActiveRecord Encryption stores as text)
      t.text    :credentials

      # JSON columns
      t.json    :field_mappings, default: {}
      t.json    :progress,       default: {}
      t.json    :error_log,      default: []

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
                   type:       :uuid,
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
