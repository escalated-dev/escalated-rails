# frozen_string_literal: true

module Escalated
  module Agent
    class MentionsController < Escalated::ApplicationController
      before_action :require_agent!

      def index
        mentions = mention_service.unread_mentions(current_user.id)
        render json: mentions.map { |m| mention_json(m) }
      end

      def mark_read
        mention_service.mark_as_read(params[:mention_ids], current_user.id)
        head :ok
      end

      def search_agents
        results = mention_service.search_agents(params[:q], limit: params.fetch(:limit, 10).to_i)
        render json: results
      end

      private

      def mention_service
        @mention_service ||= Escalated::MentionService.new
      end

      def mention_json(mention)
        {
          id: mention.id,
          reply_id: mention.reply_id,
          ticket_id: mention.reply.ticket_id,
          ticket_reference: mention.reply.ticket.reference,
          ticket_subject: mention.reply.ticket.subject,
          created_at: mention.created_at.iso8601,
          read_at: mention.read_at&.iso8601
        }
      end
    end
  end
end
