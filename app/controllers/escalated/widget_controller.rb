# frozen_string_literal: true

module Escalated
  class WidgetController < ActionController::Base
    include Escalated::ApiRateLimiting

    protect_from_forgery with: :null_session
    before_action :enforce_rate_limit!
    before_action :ensure_widget_enabled!

    # GET /support/widget/config
    def config
      render json: {
        enabled: widget_enabled?,
        color: Escalated::EscalatedSetting.get('widget_color', '#4F46E5'),
        position: Escalated::EscalatedSetting.get('widget_position', 'bottom-right'),
        greeting: Escalated::EscalatedSetting.get('widget_greeting', 'How can we help you?'),
        kb_enabled: Escalated::EscalatedSetting.get_bool('knowledge_base_enabled', default: true)
      }
    end

    # GET /support/widget/articles?q=search_term
    def articles
      scope = Escalated::Article.published.recent

      if params[:q].present?
        scope = scope.search(params[:q])
      end

      articles = scope.limit(10)

      render json: articles.map { |a|
        {
          id: a.id,
          title: a.title,
          slug: a.slug,
          excerpt: a.body&.truncate(200)
        }
      }
    end

    # GET /support/widget/articles/:slug
    def article
      article = Escalated::Article.published.find_by!(slug: params[:slug])
      article.increment_views!

      render json: {
        id: article.id,
        title: article.title,
        slug: article.slug,
        body: article.body,
        category: article.category ? { id: article.category.id, name: article.category.name } : nil
      }
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Article not found' }, status: :not_found
    end

    # POST /support/widget/tickets
    def create_ticket
      ticket = Escalated::Services::TicketService.create(
        subject: params[:subject],
        description: params[:description],
        guest_name: params[:name],
        guest_email: params[:email],
        priority: Escalated.configuration.default_priority,
        metadata: { 'source' => 'widget' }
      )

      render json: {
        reference: ticket.reference,
        guest_token: ticket.guest_token
      }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_content
    end

    # GET /support/widget/tickets/:token
    def lookup_ticket
      ticket = Escalated::Ticket.find_by!(guest_token: params[:token])

      render json: {
        reference: ticket.reference,
        subject: ticket.subject,
        status: ticket.status,
        created_at: ticket.created_at&.iso8601,
        replies: ticket.replies.public_replies.chronological.map { |r|
          {
            body: r.body,
            is_agent: r.author.respond_to?(:escalated_agent?) ? r.author.escalated_agent? : false,
            created_at: r.created_at&.iso8601
          }
        }
      }
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Ticket not found' }, status: :not_found
    end

    private

    def widget_enabled?
      Escalated::EscalatedSetting.get_bool('widget_enabled', default: false)
    end

    def ensure_widget_enabled!
      return if widget_enabled?

      render json: { error: 'Widget is disabled' }, status: :forbidden
    end

    def rate_limit_key
      "widget:ip:#{request.remote_ip}"
    end
  end
end
