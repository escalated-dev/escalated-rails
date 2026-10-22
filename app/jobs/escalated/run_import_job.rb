# frozen_string_literal: true

module Escalated
  # Runs (or resumes) one import outside the request that started it, the way
  # escalated-laravel dispatches ImportService::run onto a queue. A paused run
  # returns early and is queued again by resume; the source maps make the
  # second run skip whatever the first one already wrote.
  class RunImportJob < ApplicationJob
    queue_as :escalated

    def perform(import_job_id)
      job = Escalated::ImportJob.find_by(id: import_job_id)
      return unless job
      return if job.status == 'completed'

      Services::ImportService.new.run(job)
    rescue StandardError => e
      # Not retried: a failed job is resumed by an admin, from its cursors.
      Rails.logger.error("[Escalated::Import] Job #{import_job_id} failed: #{e.message}")
      job&.update_columns(status: 'failed', updated_at: Time.current)
    end
  end
end
