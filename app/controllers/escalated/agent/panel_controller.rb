# frozen_string_literal: true

module Escalated
  module Agent
    # The agent panel's own data routes (ADR 2026-11-05-agent-panel-data): the
    # agent's status, knowledge-base search and per-agent read markers. Each
    # acts for the signed-in agent only. JSON clients get JSON; an Inertia
    # visit goes back.
    class PanelController < Escalated::ApplicationController
      KB_DEFAULT_LIMIT = 10
      KB_MAX_LIMIT = 20

      before_action :require_agent!
      before_action :set_ticket, only: %i[mark_read mark_unread]

      # PUT/POST /agent/status: any agent, light agents included, sets their own.
      def status
        value = params[:status].to_s
        unless Escalated::AgentStatus.values.include?(value)
          return invalid('status', "The selected status is invalid (#{Escalated::AgentStatus.values.join(', ')}).")
        end

        Escalated::AgentStatus.set(escalated_current_user, value)
        answer(agent_status: value)
      end

      # GET /agent/kb/search?q=
      def kb_search
        return head(:not_found) unless Escalated::EscalatedSetting.knowledge_base_enabled?

        q = params[:q].to_s.strip
        return invalid('q', 'The q field must be between 2 and 200 characters.') unless q.length.between?(2, 200)

        limit = params[:limit].presence
        if limit && (!limit.to_s.match?(/\A\d+\z/) || !limit.to_i.between?(1, KB_MAX_LIMIT))
          return invalid('limit', "The limit field must be between 1 and #{KB_MAX_LIMIT}.")
        end

        articles = Escalated::Article.published.includes(:category)
                                     .search_text(q)
                                     .order(Escalated::Article.title_match_order(q))
                                     .order(updated_at: :desc, id: :desc)
                                     .limit(limit ? limit.to_i : KB_DEFAULT_LIMIT)

        render json: { data: articles.map { |article| article_json(article) } }
      end

      def mark_read
        Services::TicketReads.mark_read(escalated_current_user, @ticket)
        answer(is_unread: false)
      end

      def mark_unread
        Services::TicketReads.mark_unread(escalated_current_user, @ticket)
        answer(is_unread: true)
      end

      private

      # The ticket by reference or id, in the agent's ticket-access scope (404 otherwise).
      def set_ticket
        @ticket = Escalated::Ticket.find_by(reference: params[:id]) || Escalated::Ticket.find(params[:id])
      end

      def answer(json)
        return render(json: json) if request.headers['X-Inertia'].blank?

        redirect_back_or_to(escalated.agent_tickets_path)
      end

      def invalid(field, message)
        if request.headers['X-Inertia'].present?
          return redirect_back_or_to(escalated.agent_tickets_path, inertia: { errors: { field => message } })
        end

        render json: { message: message, errors: { field => [message] } }, status: :unprocessable_content
      end

      def article_json(article)
        {
          id: article.id,
          title: article.title,
          excerpt: excerpt(article.body),
          url: kb_url(article),
          category: article.category && { id: article.category.id, name: article.category.name },
          updated_at: article.updated_at&.iso8601
        }
      end

      def excerpt(html)
        text = CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(html.to_s)).gsub(/\s+/, ' ').strip
        text.length > 160 ? "#{text[0, 160].rstrip}..." : text
      end

      def kb_url(article)
        entry = Escalated::RouteList.routes['escalated.customer.kb.show']
        entry && "#{request.base_url}/#{entry[:uri].sub('{slug}', ERB::Util.url_encode(article.slug))}"
      end
    end
  end
end
