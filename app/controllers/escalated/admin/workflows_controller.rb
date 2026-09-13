# frozen_string_literal: true

module Escalated
  module Admin
    class WorkflowsController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_workflow, only: %i[show edit update destroy toggle logs dry_run]

      def index
        workflows = Escalated::Workflow.ordered
        render_page 'Escalated/Admin/Workflows/Index', {
          workflows: workflows.map { |w| workflow_json(w) }
        }
      end

      def show
        render_page 'Escalated/Admin/Workflows/Form', {
          workflow: workflow_json(@workflow),
          trigger_events: Escalated::Workflow::TRIGGER_EVENTS,
          operators: Escalated::WorkflowEngine::OPERATORS,
          action_types: Escalated::WorkflowEngine::ACTION_TYPES
        }
      end

      def new
        render_page 'Escalated/Admin/Workflows/Form', {
          workflow: nil,
          trigger_events: Escalated::Workflow::TRIGGER_EVENTS,
          operators: Escalated::WorkflowEngine::OPERATORS,
          action_types: Escalated::WorkflowEngine::ACTION_TYPES
        }
      end

      def edit
        render_page 'Escalated/Admin/Workflows/Form', {
          workflow: workflow_json(@workflow),
          trigger_events: Escalated::Workflow::TRIGGER_EVENTS,
          operators: Escalated::WorkflowEngine::OPERATORS,
          action_types: Escalated::WorkflowEngine::ACTION_TYPES
        }
      end

      def create
        workflow = Escalated::Workflow.new(workflow_params)
        if workflow.save
          redirect_to escalated.admin_workflows_path, notice: I18n.t('escalated.admin.workflow.created')
        else
          redirect_back_with_errors(workflow)
        end
      end

      def update
        if @workflow.update(workflow_params)
          redirect_to escalated.admin_workflows_path, notice: I18n.t('escalated.admin.workflow.updated')
        else
          redirect_back_with_errors(@workflow)
        end
      end

      def destroy
        @workflow.destroy!
        redirect_to escalated.admin_workflows_path, notice: I18n.t('escalated.admin.workflow.deleted')
      end

      # Flips the one column without re-validating the rest, so a workflow
      # stored before a validation was tightened can still be switched off.
      def toggle
        @workflow.update_attribute(:is_active, !@workflow.is_active)
        redirect_to escalated.admin_workflows_path,
                    notice: I18n.t("escalated.admin.workflow.#{@workflow.is_active ? 'activated' : 'deactivated'}")
      end

      def reorder
        params[:workflow_ids].each_with_index do |id, index|
          Escalated::Workflow.where(id: id).update_all(position: index)
        end
        head :ok
      end

      def logs
        logs = @workflow.workflow_logs.includes(:workflow, :ticket).recent.limit(100)
        render_page 'Escalated/Admin/Workflows/Logs', {
          workflow: workflow_json(@workflow),
          logs: logs.map { |l| log_json(l) }
        }
      end

      def dry_run
        ticket = Escalated::Ticket.find(params[:ticket_id])
        engine = Escalated::WorkflowEngine.new
        result = engine.dry_run(@workflow, ticket)

        render json: result
      end

      private

      def set_workflow
        @workflow = Escalated::Workflow.find(params[:id])
      end

      CONDITION_KEYS = %i[field operator value].freeze

      # The admin contract sends these keys top-level. They also appear under
      # `workflow` only when the host app turns on ParamsWrapper for JSON, so
      # nothing can depend on that. Conditions are { all | any: [condition] } and
      # actions are [{ type, value }]; `description` has no column and is dropped.
      def workflow_params
        params.slice(:name, :trigger_event, :is_active, :position, :conditions, :actions).permit(
          :name, :trigger_event, :is_active, :position,
          conditions: { all: CONDITION_KEYS, any: CONDITION_KEYS },
          actions: %i[type value]
        )
      end

      # Inertia's convention for a failed form visit: back to the form, with the
      # errors in the session keyed by field so useForm shows them on the inputs.
      def redirect_back_with_errors(workflow)
        redirect_back_or_to(
          escalated.admin_workflows_path,
          alert: workflow.errors.full_messages.join(', '),
          inertia: { errors: workflow.errors.to_hash(true).transform_values(&:first) }
        )
      end

      def workflow_json(workflow)
        {
          id: workflow.id, name: workflow.name,
          trigger_event: workflow.trigger_event, trigger: workflow.trigger,
          conditions: workflow.conditions, actions: workflow.actions,
          is_active: workflow.is_active, position: workflow.position,
          created_at: workflow.created_at&.iso8601, updated_at: workflow.updated_at&.iso8601
        }
      end

      def log_json(log)
        {
          id: log.id, workflow_id: log.workflow_id, ticket_id: log.ticket_id,
          trigger_event: log.trigger_event,
          event: log.event,
          workflow_name: log.workflow_name,
          ticket_reference: log.ticket_reference,
          matched: log.matched,
          actions_executed: log.actions_executed_count,
          action_details: log.action_details,
          duration_ms: log.duration_ms,
          status: log.computed_status,
          error_message: log.error_message,
          created_at: log.created_at&.iso8601
        }
      end
    end
  end
end
