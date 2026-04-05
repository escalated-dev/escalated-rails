module Escalated
  module Admin
    class ArticlesController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_article, only: [:update, :destroy]

      def index
        scope = Escalated::Article.includes(:category, :author).recent

        scope = scope.search(params[:search]) if params[:search].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(category_id: params[:category_id]) if params[:category_id].present?

        result = paginate(scope)

        render_page "Escalated/Admin/Articles/Index", {
          articles: result[:data].map { |a| article_json(a) },
          meta: result[:meta],
          filters: {
            search: params[:search],
            status: params[:status],
            category_id: params[:category_id]
          },
          categories: Escalated::ArticleCategory.ordered.map { |c| { id: c.id, name: c.name } },
          statuses: Escalated::Article.statuses.keys
        }
      end

      def create
        article = Escalated::Article.new(article_params)
        article.author = escalated_current_user

        if article.save
          redirect_to escalated.admin_articles_path, notice: I18n.t('escalated.admin.article.created')
        else
          redirect_back fallback_location: escalated.admin_articles_path,
                        alert: article.errors.full_messages.join(", ")
        end
      end

      def update
        if @article.update(article_params)
          redirect_to escalated.admin_articles_path, notice: I18n.t('escalated.admin.article.updated')
        else
          redirect_back fallback_location: escalated.admin_articles_path,
                        alert: @article.errors.full_messages.join(", ")
        end
      end

      def destroy
        @article.destroy!
        redirect_to escalated.admin_articles_path, notice: I18n.t('escalated.admin.article.deleted')
      end

      private

      def set_article
        @article = Escalated::Article.find(params[:id])
      end

      def article_params
        params.require(:article).permit(:title, :slug, :body, :status, :category_id)
      end

      def article_json(article)
        {
          id: article.id,
          title: article.title,
          slug: article.slug,
          status: article.status,
          category: article.category ? {
            id: article.category.id,
            name: article.category.name
          } : nil,
          author: article.author ? {
            id: article.author.id,
            name: article.author.respond_to?(:name) ? article.author.name : article.author.email
          } : nil,
          created_at: article.created_at&.iso8601,
          updated_at: article.updated_at&.iso8601
        }
      end
    end
  end
end
