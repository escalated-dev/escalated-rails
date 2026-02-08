module Escalated
  module Admin
    class SlaPoliciesController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_sla_policy, only: [:show, :edit, :update, :destroy]

      def index
        policies = Escalated::SlaPolicy.ordered

        render inertia: "Escalated/Admin/SlaPolicies/Index", props: {
          sla_policies: policies.map { |p| sla_policy_json(p) }
        }
      end

      def new
        render inertia: "Escalated/Admin/SlaPolicies/Form", props: {
          sla_policy: nil,
          priorities: Escalated::Ticket.priorities.keys
        }
      end

      def create
        policy = Escalated::SlaPolicy.new(sla_policy_params)

        if policy.save
          redirect_to admin_sla_policy_path(policy), notice: "SLA Policy created."
        else
          redirect_back fallback_location: new_admin_sla_policy_path,
                        alert: policy.errors.full_messages.join(", ")
        end
      end

      def show
        render inertia: "Escalated/Admin/SlaPolicies/Show", props: {
          sla_policy: sla_policy_json(@sla_policy),
          targets: @sla_policy.priority_targets,
          department_count: @sla_policy.departments.count,
          ticket_count: @sla_policy.tickets.count
        }
      end

      def edit
        render inertia: "Escalated/Admin/SlaPolicies/Form", props: {
          sla_policy: sla_policy_json(@sla_policy),
          priorities: Escalated::Ticket.priorities.keys
        }
      end

      def update
        if @sla_policy.update(sla_policy_params)
          redirect_to admin_sla_policy_path(@sla_policy), notice: "SLA Policy updated."
        else
          redirect_back fallback_location: edit_admin_sla_policy_path(@sla_policy),
                        alert: @sla_policy.errors.full_messages.join(", ")
        end
      end

      def destroy
        @sla_policy.destroy!
        redirect_to admin_sla_policies_path, notice: "SLA Policy deleted."
      end

      private

      def set_sla_policy
        @sla_policy = Escalated::SlaPolicy.find(params[:id])
      end

      def sla_policy_params
        params.require(:sla_policy).permit(
          :name, :description, :is_active, :is_default,
          first_response_hours: {},
          resolution_hours: {}
        )
      end

      def sla_policy_json(policy)
        {
          id: policy.id,
          name: policy.name,
          description: policy.description,
          is_active: policy.is_active,
          is_default: policy.is_default,
          first_response_hours: policy.first_response_hours,
          resolution_hours: policy.resolution_hours,
          targets: policy.priority_targets,
          created_at: policy.created_at&.iso8601,
          updated_at: policy.updated_at&.iso8601
        }
      end

      def admin_sla_policy_path(policy)
        escalated.admin_sla_policy_path(policy)
      end

      def new_admin_sla_policy_path
        escalated.new_admin_sla_policy_path
      end

      def edit_admin_sla_policy_path(policy)
        escalated.edit_admin_sla_policy_path(policy)
      end

      def admin_sla_policies_path
        escalated.admin_sla_policies_path
      end
    end
  end
end
