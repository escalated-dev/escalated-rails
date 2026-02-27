module Escalated
  module Admin
    class KbCategoriesController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_category, only: [:update, :destroy]

      def index
        categories = Escalated::ArticleCategory.ordered

        render inertia: "Escalated/Admin/KbCategories/Index", props: {
          categories: categories.map { |c| category_json(c) }
        }
      end

      def store
        category = Escalated::ArticleCategory.new(category_params)

        if category.save
          render json: category_json(category), status: :created
        else
          render json: { error: category.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      def update
        if @category.update(category_params)
          render json: category_json(@category)
        else
          render json: { error: @category.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      def destroy
        @category.destroy!
        render json: { success: true }
      end

      private

      def set_category
        @category = Escalated::ArticleCategory.find(params[:id])
      end

      def category_params
        params.require(:article_category).permit(:name, :description, :slug, :position)
      end

      def category_json(category)
        {
          id: category.id,
          name: category.name,
          slug: category.slug,
          description: category.description,
          position: category.position,
          article_count: category.articles.count,
          created_at: category.created_at&.iso8601,
          updated_at: category.updated_at&.iso8601
        }
      end
    end
  end
end
