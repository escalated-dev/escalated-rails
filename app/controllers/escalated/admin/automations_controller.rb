module Escalated
  module Admin
    class AutomationsController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_automation, only: [:edit, :update, :destroy]

      def index
        automations = Escalated::Automation.ordered

        render_page "Escalated/Admin/Automations/Index", {
          automations: automations.map { |a| automation_json(a) }
        }
      end

      def new
        render_page "Escalated/Admin/Automations/New", {
          condition_fields: condition_fields,
          action_types: action_types
        }
      end

      def create
        automation = Escalated::Automation.new(automation_params)

        if automation.save
          redirect_to escalated.admin_automations_path, notice: I18n.t("escalated.admin.automation.created")
        else
          redirect_back fallback_location: escalated.admin_automations_path,
                        alert: automation.errors.full_messages.join(", ")
        end
      end

      def edit
        render_page "Escalated/Admin/Automations/Edit", {
          automation: automation_json(@automation),
          condition_fields: condition_fields,
          action_types: action_types
        }
      end

      def update
        if @automation.update(automation_params)
          redirect_to escalated.admin_automations_path, notice: I18n.t("escalated.admin.automation.updated")
        else
          redirect_back fallback_location: escalated.admin_automations_path,
                        alert: @automation.errors.full_messages.join(", ")
        end
      end

      def destroy
        @automation.destroy!
        redirect_to escalated.admin_automations_path, notice: I18n.t("escalated.admin.automation.deleted")
      end

      private

      def set_automation
        @automation = Escalated::Automation.find(params[:id])
      end

      def automation_params
        params.require(:automation).permit(
          :name, :active, :position,
          conditions: [:field, :operator, :value],
          actions: [:type, :value]
        )
      end

      def automation_json(automation)
        {
          id: automation.id,
          name: automation.name,
          conditions: automation.conditions,
          actions: automation.actions,
          active: automation.active,
          position: automation.position,
          last_run_at: automation.last_run_at&.iso8601,
          created_at: automation.created_at&.iso8601,
          updated_at: automation.updated_at&.iso8601
        }
      end

      def condition_fields
        %w[
          hours_since_created
          hours_since_updated
          hours_since_assigned
          status
          priority
          assigned
          ticket_type
          subject_contains
        ]
      end

      def action_types
        %w[
          change_status
          assign
          add_tag
          change_priority
          add_note
          set_ticket_type
        ]
      end
    end
  end
end
