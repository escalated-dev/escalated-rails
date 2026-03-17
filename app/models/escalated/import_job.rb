module Escalated
  class ImportJob < ApplicationRecord
    self.table_name = Escalated.table_name("import_jobs")

    has_many :source_maps,
             class_name: "Escalated::ImportSourceMap",
             foreign_key: :import_job_id,
             dependent: :destroy

    encrypts :credentials

    serialize :credentials, coder: JSON
    serialize :field_mappings, coder: JSON
    serialize :progress, coder: JSON
    serialize :error_log, coder: JSON

    VALID_TRANSITIONS = {
      "pending"        => %w[authenticating],
      "authenticating" => %w[mapping failed],
      "mapping"        => %w[importing failed],
      "importing"      => %w[paused completed failed],
      "paused"         => %w[importing failed],
      "completed"      => [],
      "failed"         => %w[mapping],
    }.freeze

    validates :platform, presence: true
    validates :status, inclusion: { in: VALID_TRANSITIONS.keys }

    # ---------------------------------------------------------------------------
    # State machine
    # ---------------------------------------------------------------------------

    def transition_to!(new_status)
      allowed = VALID_TRANSITIONS[status || "pending"] || []

      unless allowed.include?(new_status.to_s)
        raise ArgumentError,
              "Cannot transition from '#{status}' to '#{new_status}'."
      end

      update!(status: new_status.to_s)
    end

    # ---------------------------------------------------------------------------
    # Progress helpers
    # ---------------------------------------------------------------------------

    def update_entity_progress(entity_type, processed: nil, total: nil, skipped: nil, failed: nil, cursor: nil)
      current_progress = self.progress || {}
      entity = current_progress[entity_type] || {
        "total" => 0, "processed" => 0, "skipped" => 0, "failed" => 0, "cursor" => nil
      }

      entity["processed"] = processed unless processed.nil?
      entity["total"]     = total     unless total.nil?
      entity["skipped"]   = skipped   unless skipped.nil?
      entity["failed"]    = failed    unless failed.nil?
      entity["cursor"]    = cursor    unless cursor.nil?

      current_progress[entity_type] = entity
      update!(progress: current_progress)
    end

    def entity_cursor(entity_type)
      progress&.dig(entity_type, "cursor")
    end

    def append_error(entity_type, source_id, error)
      log = self.error_log || []

      if log.size < 10_000
        log << {
          "entity_type" => entity_type,
          "source_id"   => source_id,
          "error"       => error,
          "timestamp"   => Time.current.iso8601,
        }
        update!(error_log: log)
      end
    end

    def purge_credentials!
      update!(credentials: nil)
    end

    def resumable?
      %w[paused failed].include?(status)
    end
  end
end
