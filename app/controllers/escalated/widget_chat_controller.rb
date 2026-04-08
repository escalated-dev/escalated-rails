# frozen_string_literal: true

module Escalated
  class WidgetChatController < ApplicationController
    include Escalated::ApiRateLimiting

    protect_from_forgery with: :null_session
    before_action :enforce_rate_limit!
    before_action :set_session, only: %i[message typing end_chat rate]

    # GET /widget/chat/availability
    def availability
      department_id = params[:department_id]
      routing = Services::ChatRoutingService.evaluate_routing(department_id: department_id)

      render json: {
        available: routing[:available] && !routing[:queue_full],
        queue_size: routing[:queue_size],
        offline_behavior: routing[:offline_behavior],
        queue_message: routing[:queue_message],
        offline_message: routing[:offline_message]
      }
    end

    # POST /widget/chat/start
    def start
      result = Services::ChatSessionService.start_chat(
        subject: params[:subject] || 'Live Chat',
        message: params[:message],
        name: params[:name],
        email: params[:email],
        department_id: params[:department_id],
        session_id: params[:session_id],
        metadata: { 'user_agent' => request.user_agent, 'ip' => request.remote_ip }
      )

      render json: {
        ticket_id: result[:ticket].id,
        ticket_reference: result[:ticket].reference,
        session_id: result[:session].id,
        customer_session_id: result[:session].customer_session_id,
        status: result[:session].status,
        guest_token: result[:ticket].guest_token
      }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_content
    end

    # POST /widget/chat/:session_id/message
    def message
      reply = Services::ChatSessionService.send_message(
        @session,
        body: params[:body],
        author: nil,
        is_internal: false
      )

      render json: {
        reply_id: reply.id,
        body: reply.body,
        created_at: reply.created_at&.iso8601
      }
    end

    # POST /widget/chat/:session_id/typing
    def typing
      Services::ChatSessionService.update_typing(@session, is_agent: false)
      head :no_content
    end

    # POST /widget/chat/:session_id/end
    def end_chat
      Services::ChatSessionService.end_chat(@session)
      render json: { status: 'ended' }
    end

    # POST /widget/chat/:session_id/rate
    def rate
      unless params[:rating].present? && (1..5).cover?(params[:rating].to_i)
        render json: { error: 'Rating must be between 1 and 5' }, status: :unprocessable_content
        return
      end

      Services::ChatSessionService.rate_chat(
        @session,
        rating: params[:rating].to_i,
        comment: params[:comment]
      )

      render json: { status: 'rated' }
    end

    private

    def set_session
      @session = Escalated::ChatSession.find_by!(customer_session_id: params[:session_id])
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Chat session not found' }, status: :not_found
    end

    def rate_limit_key
      "widget_chat:ip:#{request.remote_ip}"
    end
  end
end
