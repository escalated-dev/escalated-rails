module Escalated
  module Admin
    class EscalationRulesController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_rule, only: [:show, :edit, :update, :destroy]

      def index
        rules = Escalated::EscalationRule.ordered

        render inertia: "Escalated/Admin/EscalationRules/Index", props: {
          escalation_rules: rules.map { |r| rule_json(r) }
        }
      end

      def new
        render inertia: "Escalated/Admin/EscalationRules/Form", props: {
          escalation_rule: nil,
          departments: Escalated::Department.active.ordered.map { |d| { id: d.id, name: d.name } },
          agents: agent_list,
          statuses: Escalated::Ticket.statuses.keys,
          priorities: Escalated::Ticket.priorities.keys
        }
      end

      def create
        rule = Escalated::EscalationRule.new(rule_params)

        if rule.save
          redirect_to admin_escalation_rule_path(rule), notice: "Escalation rule created."
        else
          redirect_back fallback_location: new_admin_escalation_rule_path,
                        alert: rule.errors.full_messages.join(", ")
        end
      end

      def show
        render inertia: "Escalated/Admin/EscalationRules/Show", props: {
          escalation_rule: rule_json(@rule)
        }
      end

      def edit
        render inertia: "Escalated/Admin/EscalationRules/Form", props: {
          escalation_rule: rule_json(@rule),
          departments: Escalated::Department.active.ordered.map { |d| { id: d.id, name: d.name } },
          agents: agent_list,
          statuses: Escalated::Ticket.statuses.keys,
          priorities: Escalated::Ticket.priorities.keys
        }
      end

      def update
        if @rule.update(rule_params)
          redirect_to admin_escalation_rule_path(@rule), notice: "Escalation rule updated."
        else
          redirect_back fallback_location: edit_admin_escalation_rule_path(@rule),
                        alert: @rule.errors.full_messages.join(", ")
        end
      end

      def destroy
        @rule.destroy!
        redirect_to admin_escalation_rules_path, notice: "Escalation rule deleted."
      end

      private

      def set_rule
        @rule = Escalated::EscalationRule.find(params[:id])
      end

      def rule_params
        params.require(:escalation_rule).permit(
          :name, :description, :is_active, :priority,
          conditions: {},
          actions: {}
        )
      end

      def rule_json(rule)
        {
          id: rule.id,
          name: rule.name,
          description: rule.description,
          is_active: rule.is_active,
          priority: rule.priority,
          conditions: rule.conditions,
          actions: rule.actions,
          created_at: rule.created_at&.iso8601,
          updated_at: rule.updated_at&.iso8601
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

      def admin_escalation_rule_path(rule)
        escalated.admin_escalation_rule_path(rule)
      end

      def new_admin_escalation_rule_path
        escalated.new_admin_escalation_rule_path
      end

      def edit_admin_escalation_rule_path(rule)
        escalated.edit_admin_escalation_rule_path(rule)
      end

      def admin_escalation_rules_path
        escalated.admin_escalation_rules_path
      end
    end
  end
end
