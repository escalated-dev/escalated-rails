module Escalated
  module Admin
    class AutomationsController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_automation, only: [:update, :destroy]

      def index
        automations = Escalated::Automation.ordered

        render inertia: "Escalated/Admin/Automations/Index", props: {
          automations: automations.map { |a| automation_json(a) }
        }
      end

      def create
        automation = Escalated::Automation.new(automation_params)

        if automation.save
          redirect_to escalated.admin_automations_path, notice: I18n.t('escalated.admin.automation.created')
        else
          redirect_back fallback_location: escalated.admin_automations_path,
                        alert: automation.errors.full_messages.join(", ")
        end
      end

      def update
        if @automation.update(automation_params)
          redirect_to escalated.admin_automations_path, notice: I18n.t('escalated.admin.automation.updated')
        else
          redirect_back fallback_location: escalated.admin_automations_path,
                        alert: @automation.errors.full_messages.join(", ")
        end
      end

      def destroy
        @automation.destroy!
        redirect_to escalated.admin_automations_path, notice: I18n.t('escalated.admin.automation.deleted')
      end

      private

      def set_automation
        @automation = Escalated::Automation.find(params[:id])
      end

      def automation_params
        params.require(:automation).permit(
          :name, :description, :is_active, :run_on,
          conditions: [:field, :operator, :value],
          actions: [:type, :value]
        )
      end

      def automation_json(automation)
        {
          id: automation.id,
          name: automation.name,
          description: automation.description,
          is_active: automation.is_active,
          run_on: automation.run_on,
          conditions: automation.conditions,
          actions: automation.actions,
          last_run_at: automation.last_run_at&.iso8601,
          run_count: automation.run_count,
          created_at: automation.created_at&.iso8601,
          updated_at: automation.updated_at&.iso8601
        }
      end
    end
  end
end
