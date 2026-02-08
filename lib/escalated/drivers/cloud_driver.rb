require "escalated/drivers/hosted_api_client"

module Escalated
  module Drivers
    class CloudDriver
      def create_ticket(params)
        response = client.post("/tickets", {
          subject: params[:subject],
          description: params[:description],
          priority: params[:priority] || Escalated.configuration.default_priority,
          requester_email: params[:requester]&.email,
          department_id: params[:department_id],
          tag_ids: params[:tag_ids],
          metadata: params[:metadata]
        })

        build_ticket_from_response(response)
      end

      def update_ticket(ticket, params, actor:)
        reference = ticket.is_a?(String) ? ticket : ticket.reference

        response = client.patch("/tickets/#{reference}", {
          subject: params[:subject],
          description: params[:description],
          metadata: params[:metadata]
        })

        build_ticket_from_response(response)
      end

      def transition_status(ticket, new_status, actor:, note: nil)
        reference = ticket.is_a?(String) ? ticket : ticket.reference

        response = client.post("/tickets/#{reference}/status", {
          status: new_status,
          note: note
        })

        build_ticket_from_response(response)
      end

      def assign_ticket(ticket, agent, actor:)
        reference = ticket.is_a?(String) ? ticket : ticket.reference

        response = client.post("/tickets/#{reference}/assign", {
          agent_email: agent.email
        })

        build_ticket_from_response(response)
      end

      def unassign_ticket(ticket, actor:)
        reference = ticket.is_a?(String) ? ticket : ticket.reference

        response = client.post("/tickets/#{reference}/unassign")
        build_ticket_from_response(response)
      end

      def add_reply(ticket, params)
        reference = ticket.is_a?(String) ? ticket : ticket.reference

        response = client.post("/tickets/#{reference}/replies", {
          body: params[:body],
          author_email: params[:author]&.email,
          is_internal: params[:is_internal] || false
        })

        OpenStruct.new(response)
      end

      def get_ticket(id)
        response = client.get("/tickets/#{id}")
        build_ticket_from_response(response)
      end

      def list_tickets(filters = {})
        response = client.get("/tickets", filters)
        response.map { |data| build_ticket_from_response(data) }
      end

      def add_tags(ticket, tag_ids, actor:)
        reference = ticket.is_a?(String) ? ticket : ticket.reference

        response = client.post("/tickets/#{reference}/tags", {
          tag_ids: tag_ids
        })

        build_ticket_from_response(response)
      end

      def remove_tags(ticket, tag_ids, actor:)
        reference = ticket.is_a?(String) ? ticket : ticket.reference

        response = client.delete("/tickets/#{reference}/tags", {
          tag_ids: tag_ids
        })

        build_ticket_from_response(response)
      end

      def change_department(ticket, department, actor:)
        reference = ticket.is_a?(String) ? ticket : ticket.reference

        response = client.post("/tickets/#{reference}/department", {
          department_id: department.id
        })

        build_ticket_from_response(response)
      end

      def change_priority(ticket, new_priority, actor:)
        reference = ticket.is_a?(String) ? ticket : ticket.reference

        response = client.post("/tickets/#{reference}/priority", {
          priority: new_priority
        })

        build_ticket_from_response(response)
      end

      private

      def client
        @client ||= HostedApiClient.new
      end

      def build_ticket_from_response(data)
        data = data.deep_symbolize_keys if data.respond_to?(:deep_symbolize_keys)
        OpenStruct.new(data)
      end
    end
  end
end
