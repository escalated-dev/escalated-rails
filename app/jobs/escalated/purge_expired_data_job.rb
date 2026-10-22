# frozen_string_literal: true

module Escalated
  # Applies the retention settings of Admin/Settings/DataRetention (see
  # Escalated::Services::DataRetentionService). Schedule it daily; while every
  # retention is "never", the default, it only clears expired guest
  # verification codes.
  class PurgeExpiredDataJob < ApplicationJob
    queue_as :escalated_low

    def perform(dry_run: false)
      counts = Escalated::Services::DataRetentionService.new.purge(dry_run: dry_run)

      Rails.logger.info(
        "[Escalated::PurgeExpiredDataJob] #{dry_run ? 'would purge' : 'purged'} " \
        "#{counts.map { |kind, count| "#{count} #{kind}" }.join(', ')}"
      )

      counts
    end
  end
end
