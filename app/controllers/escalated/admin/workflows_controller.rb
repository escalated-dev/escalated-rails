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
        render_page 'Escalated/Admin/Workflows/Show', {
          workflow: workflow_json(@workflow),
          trigger_events: Escalated::Workflow::TRIGGER_EVENTS,
          operators: Escalated::WorkflowEngine::OPERATORS,
          action_types: Escalated::WorkflowEngine::ACTION_TYPES
        }
      end

      def new
        render_page 'Escalated/Admin/Workflows/New', {
          trigger_events: Escalated::Workflow::TRIGGER_EVENTS,
          operators: Escalated::WorkflowEngine::OPERATORS,
          action_types: Escalated::WorkflowEngine::ACTION_TYPES
        }
      end

      def edit
        render_page 'Escalated/Admin/Workflows/Edit', {
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
          redirect_back_or_to(escalated.admin_workflows_path, alert: workflow.errors.full_messages.join(', '))
        end
      end

      def update
        if @workflow.update(workflow_params)
          redirect_to escalated.admin_workflows_path, notice: I18n.t('escalated.admin.workflow.updated')
        else
          redirect_back_or_to(escalated.admin_workflows_path, alert: @workflow.errors.full_messages.join(', '))
        end
      end

      def destroy
        @workflow.destroy!
        redirect_to escalated.admin_workflows_path, notice: I18n.t('escalated.admin.workflow.deleted')
      end

      def toggle
        @workflow.update!(is_active: !@workflow.is_active)
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
        logs = @workflow.workflow_logs.recent.limit(100)
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

      def workflow_params
        params.expect(
          workflow: [:name, :trigger_event, :is_active, :position,
                     { conditions: {}, actions: [] }]
        )
      end

      def workflow_json(workflow)
        {
          id: workflow.id, name: workflow.name, trigger_event: workflow.trigger_event,
          conditions: workflow.conditions, actions: workflow.actions,
          is_active: workflow.is_active, position: workflow.position,
          created_at: workflow.created_at&.iso8601, updated_at: workflow.updated_at&.iso8601
        }
      end

      def log_json(log)
        {
          id: log.id, workflow_id: log.workflow_id, ticket_id: log.ticket_id,
          trigger_event: log.trigger_event, status: log.status,
          actions_executed: log.actions_executed, error_message: log.error_message,
          created_at: log.created_at&.iso8601
        }
      end
    end
  end
end
