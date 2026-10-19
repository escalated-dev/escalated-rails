# frozen_string_literal: true

module Escalated
  class WidgetChatController < PublicController
    include Escalated::ApiRateLimiting
    include Escalated::WidgetCors
    include Escalated::WidgetDepartments

    protect_from_forgery with: :null_session
    before_action :enforce_rate_limit!
    before_action :set_session, only: %i[message messages typing end_chat rate]

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
      if Escalated::Support::WidgetMetadata.invalid?(params[:metadata])
        return render json: { error: 'metadata must be an object with at most 50 keys' },
                      status: :unprocessable_content
      end

      return render_unknown_department unless widget_department_valid?(params[:department_id])

      host_metadata = Escalated::Support::WidgetMetadata.sanitize(params[:metadata], origin: widget_cross_origin)
      result = Services::ChatSessionService.start_chat(
        subject: params[:subject] || 'Live Chat',
        message: params[:message],
        name: params[:name],
        email: params[:email],
        department_id: params[:department_id].presence,
        metadata: (host_metadata || {}).merge('user_agent' => request.user_agent, 'ip' => request.remote_ip),
        session_metadata: host_metadata
      )

      chat = result[:session]
      render json: {
        # The token every later chat request names in its path.
        id: chat.customer_session_id,
        ticket_id: result[:ticket].id,
        ticket_reference: result[:ticket].reference,
        session_id: result[:session].id,
        customer_session_id: result[:session].customer_session_id,
        status: result[:session].status,
        guest_token: result[:ticket].guest_token,
        messages: [],
        agent: chat_agent(chat)
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

    # GET /widget/chat/:session_id/messages
    #
    # What the widget polls: the public conversation, who is answering, whether
    # they are typing, and whether the chat has ended.
    def messages
      ticket = @session.ticket
      replies = ticket.replies.public_replies.where(is_system: false)
                      .reorder(created_at: :desc, id: :desc).limit(100).includes(:author).to_a.reverse

      render json: {
        messages: replies.map do |reply|
          {
            id: reply.id,
            body: reply.body,
            is_agent: reply.author.present?,
            author: { name: reply.author ? display_name(reply.author) : ticket.guest_name },
            created_at: reply.created_at&.iso8601
          }
        end,
        agent: chat_agent(@session),
        typing: agent_typing? ? display_name(@session.agent) : nil,
        ended: @session.ended?
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

    def chat_agent(chat)
      chat.agent ? { name: display_name(chat.agent) } : nil
    end

    def agent_typing?
      @session.agent && @session.agent_typing_at.present? && @session.agent_typing_at > 5.seconds.ago
    end

    def display_name(user)
      user.respond_to?(:name) && user.name.present? ? user.name : 'Support'
    end

    def rate_limit_key
      "widget_chat:ip:#{request.remote_ip}"
    end
  end
end
