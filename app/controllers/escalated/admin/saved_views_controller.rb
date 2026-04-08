# frozen_string_literal: true

module Escalated
  module Admin
    class SavedViewsController < Escalated::ApplicationController
      before_action :require_agent!
      before_action :set_saved_view, only: %i[update destroy]

      def index
        views = Escalated::SavedView.accessible_by(escalated_current_user.id).ordered

        render json: views.map { |v| view_json(v) }
      end

      def create
        view = Escalated::SavedView.new(saved_view_params)
        view.user_id = escalated_current_user.id

        if view.save
          render json: view_json(view), status: :created
        else
          render json: { error: view.errors.full_messages.join(', ') }, status: :unprocessable_content
        end
      end

      def update
        if @saved_view.update(saved_view_params)
          render json: view_json(@saved_view)
        else
          render json: { error: @saved_view.errors.full_messages.join(', ') }, status: :unprocessable_content
        end
      end

      def destroy
        @saved_view.destroy!
        render json: { success: true }
      end

      def reorder
        params[:view_ids].each_with_index do |id, index|
          Escalated::SavedView
            .accessible_by(escalated_current_user.id)
            .where(id: id)
            .update_all(position: index)
        end

        render json: { success: true }
      end

      private

      def set_saved_view
        @saved_view = Escalated::SavedView.accessible_by(escalated_current_user.id).find(params[:id])
      end

      def saved_view_params
        params.permit(:name, :is_shared, :is_default, :icon, :color, filters: {})
      end

      def view_json(view)
        {
          id: view.id,
          name: view.name,
          filters: view.filters,
          user_id: view.user_id,
          is_shared: view.is_shared,
          is_default: view.is_default,
          position: view.position,
          icon: view.icon,
          color: view.color,
          created_at: view.created_at&.iso8601,
          updated_at: view.updated_at&.iso8601
        }
      end
    end
  end
end
