module Escalated
  module Admin
    class CapacityController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_capacity, only: [:update]

      def index
        capacities = Escalated::AgentCapacity.includes(:agent).ordered

        render_page "Escalated/Admin/Capacity/Index", {
          capacities: capacities.map { |c| capacity_json(c) }
        }
      end

      def update
        if @capacity.update(capacity_params)
          redirect_to escalated.admin_capacity_index_path, notice: I18n.t('escalated.admin.capacity.updated')
        else
          redirect_back fallback_location: escalated.admin_capacity_index_path,
                        alert: @capacity.errors.full_messages.join(", ")
        end
      end

      private

      def set_capacity
        @capacity = Escalated::AgentCapacity.find(params[:id])
      end

      def capacity_params
        params.require(:agent_capacity).permit(:max_concurrent)
      end

      def capacity_json(capacity)
        {
          id: capacity.id,
          max_concurrent: capacity.max_concurrent,
          current_count: capacity.current_count,
          agent: capacity.agent ? {
            id: capacity.agent.id,
            name: capacity.agent.respond_to?(:name) ? capacity.agent.name : capacity.agent.email,
            email: capacity.agent.email
          } : nil,
          updated_at: capacity.updated_at&.iso8601
        }
      end
    end
  end
end
