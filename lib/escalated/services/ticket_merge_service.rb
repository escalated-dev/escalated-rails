module Escalated
  module Services
    class TicketMergeService
      def merge(source, target, merged_by_user_id: nil)
        ActiveRecord::Base.transaction do
          # Move all replies from source to target
          Escalated::Reply.where(ticket: source).update_all(ticket_id: target.id)

          # System note on target
          Escalated::Reply.create!(
            ticket: target,
            body: "Ticket #{source.reference} was merged into this ticket.",
            is_internal: true,
            is_system: true,
            is_pinned: false
          )

          # System note on source
          Escalated::Reply.create!(
            ticket: source,
            body: "This ticket was merged into #{target.reference}.",
            is_internal: true,
            is_system: true,
            is_pinned: false
          )

          # Close source and set merged_into
          source.update!(status: :closed, merged_into: target)
        end
      end
    end
  end
end
