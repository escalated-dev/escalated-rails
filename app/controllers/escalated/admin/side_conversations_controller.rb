module Escalated
  module Admin
    class SideConversationsController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_ticket
      before_action :set_conversation, only: [:reply, :close]

      def index
        conversations = @ticket.side_conversations.includes(:replies).ordered

        render json: conversations.map { |c| conversation_json(c) }
      end

      def store
        conversation = @ticket.side_conversations.new(
          subject: params[:subject],
          body: params[:body],
          channel: params[:channel] || "email",
          created_by: escalated_current_user.id
        )

        if conversation.save
          render json: conversation_json(conversation), status: :created
        else
          render json: { error: conversation.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      def reply
        reply = @conversation.replies.create!(
          body: params[:body],
          author_id: escalated_current_user.id,
          direction: "outbound"
        )

        render json: {
          id: reply.id,
          body: reply.body,
          direction: reply.direction,
          created_at: reply.created_at&.iso8601
        }, status: :created
      end

      def close
        @conversation.update!(status: "closed", closed_at: Time.current)

        render json: conversation_json(@conversation)
      end

      private

      def set_ticket
        @ticket = Escalated::Ticket.find(params[:ticket_id])
      end

      def set_conversation
        @conversation = @ticket.side_conversations.find(params[:conversation_id])
      end

      def conversation_json(conversation)
        {
          id: conversation.id,
          subject: conversation.subject,
          body: conversation.body,
          channel: conversation.channel,
          status: conversation.status,
          created_at: conversation.created_at&.iso8601,
          closed_at: conversation.closed_at&.iso8601,
          replies_count: conversation.replies.count
        }
      end
    end
  end
end
