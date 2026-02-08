module Escalated
  module Admin
    class CannedResponsesController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_canned_response, only: [:update, :destroy]

      def index
        responses = Escalated::CannedResponse.ordered

        render inertia: "Escalated/Admin/CannedResponses/Index", props: {
          canned_responses: responses.map { |r| canned_response_json(r) }
        }
      end

      def create
        response = Escalated::CannedResponse.new(canned_response_params)
        response.created_by = escalated_current_user.id

        if response.save
          redirect_to admin_canned_responses_path, notice: "Canned response created."
        else
          redirect_back fallback_location: admin_canned_responses_path,
                        alert: response.errors.full_messages.join(", ")
        end
      end

      def update
        if @canned_response.update(canned_response_params)
          redirect_to admin_canned_responses_path, notice: "Canned response updated."
        else
          redirect_back fallback_location: admin_canned_responses_path,
                        alert: @canned_response.errors.full_messages.join(", ")
        end
      end

      def destroy
        @canned_response.destroy!
        redirect_to admin_canned_responses_path, notice: "Canned response deleted."
      end

      private

      def set_canned_response
        @canned_response = Escalated::CannedResponse.find(params[:id])
      end

      def canned_response_params
        params.require(:canned_response).permit(:title, :body, :shortcode, :category, :is_shared)
      end

      def canned_response_json(response)
        {
          id: response.id,
          title: response.title,
          body: response.body,
          shortcode: response.shortcode,
          category: response.category,
          is_shared: response.is_shared,
          creator: response.creator ? {
            id: response.creator.id,
            name: response.creator.respond_to?(:name) ? response.creator.name : response.creator.email
          } : nil,
          created_at: response.created_at&.iso8601,
          updated_at: response.updated_at&.iso8601
        }
      end

      def admin_canned_responses_path
        escalated.admin_canned_responses_path
      end
    end
  end
end
