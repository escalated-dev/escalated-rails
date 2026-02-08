module Escalated
  module Admin
    class DepartmentsController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_department, only: [:show, :edit, :update, :destroy]

      def index
        departments = Escalated::Department.ordered

        render inertia: "Escalated/Admin/Departments/Index", props: {
          departments: departments.map { |d| department_json(d) }
        }
      end

      def new
        render inertia: "Escalated/Admin/Departments/Form", props: {
          department: nil,
          sla_policies: Escalated::SlaPolicy.active.ordered.map { |p| { id: p.id, name: p.name } },
          agents: agent_list
        }
      end

      def create
        department = Escalated::Department.new(department_params)

        if department.save
          sync_agents(department, params[:agent_ids])
          redirect_to admin_department_path(department), notice: "Department created."
        else
          redirect_back fallback_location: new_admin_department_path,
                        alert: department.errors.full_messages.join(", ")
        end
      end

      def show
        render inertia: "Escalated/Admin/Departments/Show", props: {
          department: department_json(@department),
          agents: @department.agents.map { |a|
            { id: a.id, name: a.respond_to?(:name) ? a.name : a.email, email: a.email }
          },
          stats: {
            total_tickets: @department.tickets.count,
            open_tickets: @department.open_ticket_count,
            agent_count: @department.agent_count
          }
        }
      end

      def edit
        render inertia: "Escalated/Admin/Departments/Form", props: {
          department: department_json(@department),
          sla_policies: Escalated::SlaPolicy.active.ordered.map { |p| { id: p.id, name: p.name } },
          agents: agent_list,
          current_agent_ids: @department.agents.pluck(:id)
        }
      end

      def update
        if @department.update(department_params)
          sync_agents(@department, params[:agent_ids]) if params.key?(:agent_ids)
          redirect_to admin_department_path(@department), notice: "Department updated."
        else
          redirect_back fallback_location: edit_admin_department_path(@department),
                        alert: @department.errors.full_messages.join(", ")
        end
      end

      def destroy
        @department.destroy!
        redirect_to admin_departments_path, notice: "Department deleted."
      end

      private

      def set_department
        @department = Escalated::Department.find(params[:id])
      end

      def department_params
        params.require(:department).permit(:name, :description, :email, :is_active, :default_sla_policy_id)
      end

      def sync_agents(department, agent_ids)
        return unless agent_ids.present?

        agents = Escalated.configuration.user_model.where(id: agent_ids)
        department.agents = agents
      end

      def department_json(department)
        {
          id: department.id,
          name: department.name,
          slug: department.slug,
          description: department.description,
          email: department.email,
          is_active: department.is_active,
          default_sla_policy: department.default_sla_policy ? {
            id: department.default_sla_policy.id,
            name: department.default_sla_policy.name
          } : nil,
          agent_count: department.agent_count,
          open_ticket_count: department.open_ticket_count,
          created_at: department.created_at&.iso8601
        }
      end

      def agent_list
        if Escalated.configuration.user_model.respond_to?(:escalated_agents)
          Escalated.configuration.user_model.escalated_agents.map { |a|
            { id: a.id, name: a.respond_to?(:name) ? a.name : a.email, email: a.email }
          }
        else
          []
        end
      end

      def admin_department_path(department)
        escalated.admin_department_path(department)
      end

      def new_admin_department_path
        escalated.new_admin_department_path
      end

      def edit_admin_department_path(department)
        escalated.edit_admin_department_path(department)
      end

      def admin_departments_path
        escalated.admin_departments_path
      end
    end
  end
end
