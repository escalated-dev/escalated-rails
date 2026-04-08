# frozen_string_literal: true

module Escalated
  module Admin
    class ChatController < Escalated::ApplicationController
      before_action :require_agent!
      before_action :set_session, only: %i[accept end_chat transfer message typing]

      # GET /admin/chat
      def index
        sessions = Escalated::ChatSession.active.includes(:ticket, :agent).recent

        render json: {
          sessions: sessions.map { |s| session_json(s) },
          agent_status: current_agent_status
        }
      end

      # GET /admin/chat/queue
      def queue
        sessions = Escalated::ChatSession.waiting.includes(:ticket).recent

        render json: {
          queue: sessions.map { |s| session_json(s) },
          queue_size: sessions.size
        }
      end

      # POST /admin/chat/:id/accept
      def accept
        unless @session.waiting?
          render json: { error: 'Chat is not in waiting state' }, status: :unprocessable_content
          return
        end

        Services::ChatSessionService.assign_agent(@session, escalated_current_user.id)
        Services::CapacityService.new.increment_load(escalated_current_user.id, channel: 'chat')

        render json: { session: session_json(@session.reload) }
      end

      # POST /admin/chat/:id/end
      def end_chat
        Services::ChatSessionService.end_chat(@session, ended_by: escalated_current_user)
        render json: { session: session_json(@session.reload) }
      end

      # POST /admin/chat/:id/transfer
      def transfer
        new_agent_id = params[:agent_id]
        unless new_agent_id
          render json: { error: 'agent_id is required' }, status: :unprocessable_content
          return
        end

        Services::ChatSessionService.transfer_chat(@session, new_agent_id)
        render json: { session: session_json(@session.reload) }
      end

      # POST /admin/chat/update_status
      def update_status
        profile = Escalated::AgentProfile.find_or_create_by(user_id: escalated_current_user.id) do |p|
          p.agent_type = 'full'
        end

        unless Escalated::AgentProfile::CHAT_STATUSES.include?(params[:status])
          render json: { error: 'Invalid status' }, status: :unprocessable_content
          return
        end

        profile.update!(chat_status: params[:status])
        render json: { status: profile.chat_status }
      end

      # POST /admin/chat/:id/message
      def message
        reply = Services::ChatSessionService.send_message(
          @session,
          body: params[:body],
          author: escalated_current_user,
          is_internal: [true, 'true'].include?(params[:is_internal])
        )

        render json: { reply: reply_json(reply) }
      end

      # POST /admin/chat/:id/typing
      def typing
        Services::ChatSessionService.update_typing(@session, is_agent: true)
        head :no_content
      end

      private

      def set_session
        @session = Escalated::ChatSession.find(params[:id])
      end

      def current_agent_status
        profile = Escalated::AgentProfile.find_by(user_id: escalated_current_user.id)
        profile&.chat_status || 'offline'
      end

      def session_json(session)
        {
          id: session.id,
          ticket_id: session.ticket_id,
          ticket_reference: session.ticket&.reference,
          ticket_subject: session.ticket&.subject,
          customer_session_id: session.customer_session_id,
          agent_id: session.agent_id,
          status: session.status,
          started_at: session.started_at&.iso8601,
          ended_at: session.ended_at&.iso8601,
          duration: session.duration&.to_i,
          rating: session.rating,
          created_at: session.created_at&.iso8601
        }
      end

      def reply_json(reply)
        {
          id: reply.id,
          body: reply.body,
          is_internal: reply.is_internal,
          author: if reply.author
                    {
                      id: reply.author.id,
                      name: reply.author.respond_to?(:name) ? reply.author.name : reply.author.email
                    }
                  end,
          created_at: reply.created_at&.iso8601
        }
      end
    end
  end
end
