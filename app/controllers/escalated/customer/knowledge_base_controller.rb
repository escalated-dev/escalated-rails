# frozen_string_literal: true

module Escalated
  module Customer
    # The customer-facing knowledge base: Customer/KnowledgeBase/Index and
    # Article, as escalated-laravel's Customer\KnowledgeBaseController serves
    # them. Only published articles are shown.
    class KnowledgeBaseController < Escalated::ApplicationController
      before_action :ensure_knowledge_base_accessible!
      before_action :set_article, only: %i[show feedback]

      def index
        scope = Escalated::Article.published.includes(:category)
        scope = scope.search(params[:search]) if params[:search].present?
        scope = scope.where(category_id: params[:category]) if params[:category].present?
        scope = scope.order(published_at: :desc, id: :desc)

        result = paginate(scope, per_page: 15)

        render_page 'Escalated/Customer/KnowledgeBase/Index', {
          categories: categories_json,
          articles: paginated_page(result, result[:data].map { |a| article_json(a) }),
          filters: params.permit(:search, :category).to_h.compact_blank
        }
      end

      def show
        @article.increment_views!

        related = Escalated::Article.published
                                    .where(category_id: @article.category_id)
                                    .where.not(id: @article.id)
                                    .order(:id)
                                    .limit(5)

        render_page 'Escalated/Customer/KnowledgeBase/Article', {
          article: article_json(@article).merge(body: @article.body),
          related: related.map { |a| { id: a.id, title: a.title, slug: a.slug } },
          feedbackEnabled: Escalated::EscalatedSetting.knowledge_base_feedback_enabled?
        }
      end

      def feedback
        raise ActiveRecord::RecordNotFound unless Escalated::EscalatedSetting.knowledge_base_feedback_enabled?
        unless [true, false].include?(helpful_param)
          return redirect_back_or_to(escalated.customer_kb_article_path(@article.slug),
                                     inertia: { errors: { 'helpful' => 'The helpful field must be true or false.' } })
        end

        helpful_param ? @article.mark_helpful! : @article.mark_not_helpful!

        redirect_back_or_to(escalated.customer_kb_article_path(@article.slug),
                            notice: I18n.t('escalated.knowledge_base.feedback_thanks'))
      end

      private

      # Laravel answers a disabled knowledge base with a 404, and a private one
      # with a 403 to anyone not signed in.
      def ensure_knowledge_base_accessible!
        raise ActiveRecord::RecordNotFound unless Escalated::EscalatedSetting.knowledge_base_enabled?
        return if Escalated::EscalatedSetting.knowledge_base_public? || escalated_current_user

        user_not_authorized
      end

      def set_article
        @article = Escalated::Article.published.includes(:category).find_by!(slug: params[:slug])
      end

      def helpful_param
        value = params[:helpful]
        return value if [true, false].include?(value)

        { 'true' => true, '1' => true, 'false' => false, '0' => false }[value.to_s]
      end

      def categories_json
        counts = Escalated::Article.published.group(:category_id).count

        Escalated::ArticleCategory.roots.ordered.map do |category|
          {
            id: category.id,
            name: category.name,
            slug: category.slug,
            description: category.description,
            position: category.position,
            articles_count: counts.fetch(category.id, 0)
          }
        end
      end

      def category_json(category)
        category && { id: category.id, name: category.name, slug: category.slug }
      end

      def article_json(article)
        {
          id: article.id,
          title: article.title,
          slug: article.slug,
          category_id: article.category_id,
          category: category_json(article.category),
          view_count: article.view_count,
          helpful_count: article.helpful_count,
          not_helpful_count: article.not_helpful_count,
          published_at: article.published_at&.iso8601
        }
      end
    end
  end
end
