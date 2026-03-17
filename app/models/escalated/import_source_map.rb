module Escalated
  class ImportSourceMap < ApplicationRecord
    self.table_name = Escalated.table_name("import_source_maps")

    # No updated_at column — this is an append-only mapping table.
    self.ignored_columns += ["updated_at"] if respond_to?(:ignored_columns)

    belongs_to :import_job,
               class_name: "Escalated::ImportJob",
               foreign_key: :import_job_id

    validates :import_job_id, presence: true
    validates :entity_type,   presence: true
    validates :source_id,     presence: true
    validates :escalated_id,  presence: true
    validates :source_id,
              uniqueness: { scope: [:import_job_id, :entity_type],
                            message: "has already been imported for this job and entity type" }

    # ---------------------------------------------------------------------------
    # Class-level lookup helpers
    # ---------------------------------------------------------------------------

    # Returns the escalated_id (internal ID) for a previously imported record,
    # or nil if it hasn't been imported yet.
    #
    # @param job_id      [String]  UUID of the ImportJob
    # @param entity_type [String]  e.g. "tickets", "contacts"
    # @param source_id   [String]  External platform ID
    # @return            [String, nil]
    def self.resolve(job_id, entity_type, source_id)
      where(import_job_id: job_id, entity_type: entity_type, source_id: source_id)
        .pick(:escalated_id)
    end

    # Returns true if the record has been imported in this job.
    #
    # @param job_id      [String]
    # @param entity_type [String]
    # @param source_id   [String]
    # @return            [Boolean]
    def self.imported?(job_id, entity_type, source_id)
      resolve(job_id, entity_type, source_id).present?
    end
  end
end
