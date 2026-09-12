# frozen_string_literal: true

module Escalated
  class ImportJob < ApplicationRecord
    self.table_name = Escalated.table_name('import_jobs')

    # Carried here rather than as a column default: MySQL forbids a default on a
    # JSON column, so a database default made the engine impossible to install
    # there at all. Every adapter honours this one the same way.
    attribute :field_mappings, default: -> { {} }
    attribute :progress, default: -> { {} }
    attribute :error_log, default: -> { [] }

    has_many :source_maps,
             class_name: 'Escalated::ImportSourceMap',
             dependent: :destroy

    encrypts :credentials

    # The primary key is a uuid on PostgreSQL and a 36-character string
    # elsewhere, because MySQL has no uuid type. Generating it here means the
    # value is the same shape on every adapter and no database-side default is
    # needed -- PostgreSQL's own default would otherwise be the only thing
    # filling it in.
    before_create :assign_uuid_primary_key

    def assign_uuid_primary_key
      self.id = SecureRandom.uuid if id.blank?
    end
    private :assign_uuid_primary_key

    VALID_TRANSITIONS = {
      'pending' => %w[authenticating],
      'authenticating' => %w[mapping failed],
      'mapping' => %w[importing failed],
      'importing' => %w[paused completed failed],
      'paused' => %w[importing failed],
      'completed' => [],
      'failed' => %w[mapping]
    }.freeze

    validates :platform, presence: true
    validates :status, inclusion: { in: VALID_TRANSITIONS.keys }

    # ---------------------------------------------------------------------------
    # State machine
    # ---------------------------------------------------------------------------

    def transition_to!(new_status)
      allowed = VALID_TRANSITIONS[status || 'pending'] || []

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
      current_progress = progress || {}
      entity = current_progress[entity_type] || {
        'total' => 0, 'processed' => 0, 'skipped' => 0, 'failed' => 0, 'cursor' => nil
      }

      entity['processed'] = processed unless processed.nil?
      entity['total']     = total     unless total.nil?
      entity['skipped']   = skipped   unless skipped.nil?
      entity['failed']    = failed    unless failed.nil?
      entity['cursor']    = cursor    unless cursor.nil?

      current_progress[entity_type] = entity
      update!(progress: current_progress)
    end

    def entity_cursor(entity_type)
      progress&.dig(entity_type, 'cursor')
    end

    def append_error(entity_type, source_id, error)
      log = error_log || []

      return unless log.size < 10_000

      log << {
        'entity_type' => entity_type,
        'source_id' => source_id,
        'error' => error,
        'timestamp' => Time.current.iso8601
      }
      update!(error_log: log)
    end

    def purge_credentials!
      update!(credentials: nil)
    end

    def resumable?
      %w[paused failed].include?(status)
    end
  end
end
