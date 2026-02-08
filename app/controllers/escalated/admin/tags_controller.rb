module Escalated
  module Admin
    class TagsController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_tag, only: [:update, :destroy]

      def index
        tags = Escalated::Tag.ordered

        render inertia: "Escalated/Admin/Tags/Index", props: {
          tags: tags.map { |t| tag_json(t) }
        }
      end

      def create
        tag = Escalated::Tag.new(tag_params)

        if tag.save
          redirect_to admin_tags_path, notice: "Tag created."
        else
          redirect_back fallback_location: admin_tags_path,
                        alert: tag.errors.full_messages.join(", ")
        end
      end

      def update
        if @tag.update(tag_params)
          redirect_to admin_tags_path, notice: "Tag updated."
        else
          redirect_back fallback_location: admin_tags_path,
                        alert: @tag.errors.full_messages.join(", ")
        end
      end

      def destroy
        @tag.destroy!
        redirect_to admin_tags_path, notice: "Tag deleted."
      end

      private

      def set_tag
        @tag = Escalated::Tag.find(params[:id])
      end

      def tag_params
        params.require(:tag).permit(:name, :color, :description)
      end

      def tag_json(tag)
        {
          id: tag.id,
          name: tag.name,
          slug: tag.slug,
          color: tag.color,
          description: tag.description,
          ticket_count: tag.ticket_count,
          created_at: tag.created_at&.iso8601
        }
      end

      def admin_tags_path
        escalated.admin_tags_path
      end
    end
  end
end
