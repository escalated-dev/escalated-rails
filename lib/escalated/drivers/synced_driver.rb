require "escalated/drivers/local_driver"
require "escalated/drivers/hosted_api_client"

module Escalated
  module Drivers
    class SyncedDriver < LocalDriver
      def create_ticket(params)
        ticket = super
        sync_to_cloud(:create_ticket, ticket_payload(ticket))
        ticket
      end

      def update_ticket(ticket, params, actor:)
        result = super
        sync_to_cloud(:update_ticket, ticket_payload(result))
        result
      end

      def transition_status(ticket, new_status, actor:, note: nil)
        result = super
        sync_to_cloud(:transition_status, {
          ticket_reference: result.reference,
          status: new_status,
          note: note
        })
        result
      end

      def assign_ticket(ticket, agent, actor:)
        result = super
        sync_to_cloud(:assign_ticket, {
          ticket_reference: result.reference,
          agent_email: agent.email
        })
        result
      end

      def unassign_ticket(ticket, actor:)
        result = super
        sync_to_cloud(:unassign_ticket, {
          ticket_reference: result.reference
        })
        result
      end

      def add_reply(ticket, params)
        reply = super
        sync_to_cloud(:add_reply, {
          ticket_reference: ticket.reference,
          body: reply.body,
          author_email: reply.author&.email,
          is_internal: reply.is_internal
        })
        reply
      end

      def add_tags(ticket, tag_ids, actor:)
        result = super
        sync_to_cloud(:add_tags, {
          ticket_reference: result.reference,
          tag_names: result.tags.pluck(:name)
        })
        result
      end

      def remove_tags(ticket, tag_ids, actor:)
        result = super
        sync_to_cloud(:remove_tags, {
          ticket_reference: result.reference,
          tag_names: result.tags.pluck(:name)
        })
        result
      end

      def change_department(ticket, department, actor:)
        result = super
        sync_to_cloud(:change_department, {
          ticket_reference: result.reference,
          department_name: department.name
        })
        result
      end

      def change_priority(ticket, new_priority, actor:)
        result = super
        sync_to_cloud(:change_priority, {
          ticket_reference: result.reference,
          priority: new_priority
        })
        result
      end

      private

      def sync_to_cloud(action, payload)
        HostedApiClient.emit(action, payload)
      rescue StandardError => e
        Rails.logger.error("[Escalated::SyncedDriver] Cloud sync failed for #{action}: #{e.message}")
        ActiveSupport::Notifications.instrument("escalated.sync.failed", {
          action: action,
          error: e.message
        })
        # Local operation already succeeded - don't re-raise
      end

      def ticket_payload(ticket)
        {
          reference: ticket.reference,
          subject: ticket.subject,
          description: ticket.description,
          status: ticket.status,
          priority: ticket.priority,
          requester_email: ticket.requester&.email,
          assignee_email: ticket.assignee&.email,
          department_name: ticket.department&.name,
          tag_names: ticket.tags.pluck(:name),
          metadata: ticket.metadata,
          created_at: ticket.created_at&.iso8601,
          updated_at: ticket.updated_at&.iso8601
        }
      end
    end
  end
end
