module Escalated
  class PurgeActivitiesJob < ActiveJob::Base
    queue_as :escalated_low

    RETENTION_DAYS = 180

    def perform(retention_days: RETENTION_DAYS)
      cutoff = retention_days.days.ago

      # Only purge activities for closed tickets
      count = Escalated::TicketActivity
        .joins(:ticket)
        .where(escalated_tickets: { status: :closed })
        .where("#{Escalated.table_name('ticket_activities')}.created_at < ?", cutoff)
        .delete_all

      Rails.logger.info(
        "[Escalated::PurgeActivitiesJob] Purged #{count} activities older than #{retention_days} days"
      )

      { purged_count: count }
    end
  end
end
