# frozen_string_literal: true

module Escalated
  # Whether the host schedules Escalated's recurring jobs.
  #
  # Rails has no in-process scheduler an engine can register with, so SLA
  # checks, escalation rules, automations and snooze wake-ups only run when the
  # host schedules them (Solid Queue recurring tasks, sidekiq-cron, whenever or
  # cron). Escalated::CheckSlaJob records a heartbeat each time it runs; a
  # missing heartbeat, or one older than STALE_AFTER, means nothing is
  # scheduled. #status is the `scheduler` prop of the admin Settings,
  # Reports and Reports dashboard pages, and the `scheduler` key of the API
  # dashboard.
  module SchedulerHealth
    HEARTBEAT_KEY = 'scheduler_heartbeat_at'
    STALE_AFTER = 15 * 60 # seconds

    # What to schedule, and how often (docs/operations.md, "Required: schedule
    # the recurring jobs").
    COMMANDS = [
      { command: 'Escalated::CheckSlaJob', interval: 'every minute' },
      { command: 'Escalated::EvaluateEscalationsJob', interval: 'every 5 minutes' },
      { command: 'Escalated::RunAutomationsJob', interval: 'every 5 minutes' },
      { command: 'Escalated::WakeSnoozedTicketsJob', interval: 'every minute' },
      { command: 'Escalated::CloseResolvedJob', interval: 'daily' },
      { command: 'Escalated::PurgeActivitiesJob', interval: 'weekly' }
    ].freeze

    class << self
      # Called by Escalated::CheckSlaJob. A failure to write is logged, never
      # raised: the SLA check itself must still run.
      def beat!(at = Time.current)
        Escalated::EscalatedSetting.set(HEARTBEAT_KEY, at.utc.iso8601)
      rescue StandardError => e
        Rails.logger.warn("[Escalated::SchedulerHealth] Could not record the scheduler heartbeat: #{e.message}")
        nil
      end

      def last_run_at
        value = Escalated::EscalatedSetting.get(HEARTBEAT_KEY)
        value.present? ? Time.zone.parse(value.to_s) : nil
      rescue ArgumentError
        nil
      end

      # { healthy:, last_run_at:, message:, commands: }, or nil when it cannot
      # tell (the settings table is not migrated yet).
      def status(now: Time.current)
        last = last_run_at
        healthy = !last.nil? && last >= now - STALE_AFTER

        {
          healthy: healthy,
          last_run_at: last&.utc&.iso8601,
          message: message(healthy, last),
          commands: COMMANDS.map(&:dup)
        }
      rescue ActiveRecord::ActiveRecordError
        nil
      end

      # #status, logging a warning while the jobs are not running.
      def status_with_warning(now: Time.current)
        result = status(now: now)
        Rails.logger.warn("[Escalated] #{result[:message]}") if result && !result[:healthy]
        result
      end

      private

      def message(healthy, last)
        return 'Escalated\'s recurring jobs are running.' if healthy

        seen = if last
                 "the SLA check last ran at #{last.utc.iso8601}, more than 15 minutes ago"
               else
                 'the SLA check has never run'
               end
        "Escalated's recurring jobs are not running: #{seen}. SLA checks, escalation rules, " \
          'automations and snooze wake-ups only run when your app schedules them. Schedule ' \
          "#{COMMANDS.map { |c| "#{c[:command]} (#{c[:interval]})" }.join(', ')} with Solid Queue " \
          'recurring tasks, sidekiq-cron, whenever or cron (see "Required: schedule the recurring jobs" ' \
          'in docs/operations.md).'
      end
    end
  end
end
