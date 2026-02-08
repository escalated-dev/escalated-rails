module Escalated
  class CloseResolvedJob < ActiveJob::Base
    queue_as :escalated

    def perform
      days = Escalated.configuration.auto_close_resolved_after_days
      return if days.nil? || days <= 0

      cutoff = days.days.ago

      tickets = Escalated::Ticket
        .where(status: :resolved)
        .where("resolved_at < ?", cutoff)

      count = 0

      tickets.find_each do |ticket|
        ActiveRecord::Base.transaction do
          ticket.update!(status: :closed, closed_at: Time.current)

          ticket.activities.create!(
            action: "status_changed",
            causer: nil,
            details: {
              from: "resolved",
              to: "closed",
              reason: "auto_closed",
              note: "Automatically closed after #{days} days in resolved status"
            }
          )

          ticket.replies.create!(
            body: "This ticket was automatically closed after #{days} days in resolved status. " \
                  "If you need further assistance, please reopen or create a new ticket.",
            author: nil,
            is_internal: false,
            is_system: true
          )
        end

        count += 1
      end

      Rails.logger.info(
        "[Escalated::CloseResolvedJob] Auto-closed #{count} tickets resolved before #{cutoff}"
      )

      { closed_count: count }
    end
  end
end
