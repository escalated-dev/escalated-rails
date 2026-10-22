# frozen_string_literal: true

module Escalated
  module Admin
    class ArticlesController < Escalated::ApplicationController
      include Escalated::KnowledgeBaseGuard
      include Escalated::InertiaForms

      FIELDS = %i[title slug body status category_id].freeze
      STATUSES = %w[draft published].freeze

      before_action :require_admin!
      before_action :require_knowledge_base_enabled!
      before_action :set_article, only: %i[edit update destroy]

      def index
        scope = Escalated::Article.includes(:category, :author).recent

        scope = scope.search(params[:search]) if params[:search].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(category_id: params[:category_id]) if params[:category_id].present?

        result = paginate(scope)

        render_page 'Escalated/Admin/KnowledgeBase/Articles/Index', {
          articles: paginated_page(result, result[:data].map { |a| article_json(a) }),
          filters: {
            search: params[:search],
            status: params[:status],
            category_id: params[:category_id]
          },
          categories: category_options
        }
      end

      def new
        render_page 'Escalated/Admin/KnowledgeBase/Articles/Form', { article: nil, categories: category_options }
      end

      def edit
        render_page 'Escalated/Admin/KnowledgeBase/Articles/Form', {
          article: article_json(@article).merge(body: @article.body),
          categories: category_options
        }
      end

      def create
        attributes = article_params
        errors = validate(attributes)
        return redirect_back_with_form_errors(errors, escalated.new_admin_article_path) if errors.any?

        article = Escalated::Article.new(attributes)
        article.author = escalated_current_user
        article.published_at = Time.current if article.status == 'published'

        if article.save
          redirect_to escalated.admin_articles_path, notice: I18n.t('escalated.admin.article.created')
        else
          redirect_back_with_form_errors(record_errors(article), escalated.new_admin_article_path)
        end
      end

      def update
        attributes = article_params
        errors = validate(attributes)
        return redirect_back_with_form_errors(errors, escalated.edit_admin_article_path(@article)) if errors.any?

        @article.assign_attributes(attributes)
        @article.published_at ||= Time.current if @article.status == 'published'

        if @article.save
          redirect_to escalated.admin_articles_path, notice: I18n.t('escalated.admin.article.updated')
        else
          redirect_back_with_form_errors(record_errors(@article), escalated.edit_admin_article_path(@article))
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

      # The body the shared form posts, as escalated-laravel reads it. A blank
      # slug is derived from the title; a blank category files it under none.
      def article_params
        attributes = form_source(:article, FIELDS).permit(*FIELDS).to_h.symbolize_keys
        attributes[:category_id] = attributes[:category_id].presence if attributes.key?(:category_id)
        if attributes.key?(:slug) || attributes.key?(:title)
          attributes[:slug] = attributes[:slug].presence || attributes[:title].to_s.parameterize
        end
        attributes
      end

      # The rules escalated-laravel's ArticleController validates with.
      def validate(attributes)
        errors = {}
        errors['title'] = 'The title field is required.' if attributes[:title].blank?
        unless STATUSES.include?(attributes[:status])
          errors['status'] = "The status must be one of: #{STATUSES.join(', ')}."
        end
        if attributes[:category_id] && !Escalated::ArticleCategory.exists?(id: attributes[:category_id])
          errors['category_id'] = 'The selected category does not exist.'
        end
        errors
      end

      def category_options
        Escalated::ArticleCategory.ordered.map { |c| { id: c.id, name: c.name } }
      end

      def article_json(article)
        {
          id: article.id,
          title: article.title,
          slug: article.slug,
          status: article.status,
          category_id: article.category_id,
          view_count: article.view_count,
          helpful_count: article.helpful_count,
          not_helpful_count: article.not_helpful_count,
          published_at: article.published_at&.iso8601,
          category: if article.category
                      {
                        id: article.category.id,
                        name: article.category.name
                      }
                    end,
          author: if article.author
                    {
                      id: article.author.id,
                      name: article.author.respond_to?(:name) ? article.author.name : article.author.email
                    }
                  end,
          created_at: article.created_at&.iso8601,
          updated_at: article.updated_at&.iso8601
        }
      end
    end
  end
end
