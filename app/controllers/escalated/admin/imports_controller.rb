module Escalated
  module Admin
    class ImportsController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_import_job, only: [:show, :start, :pause, :resume, :destroy]

      # GET /admin/imports
      def index
        jobs = Escalated::ImportJob
          .order(created_at: :desc)
          .limit(100)

        render_page "Escalated/Admin/Imports/Index", {
          jobs:     jobs.map { |j| job_json(j) },
          adapters: import_service.available_adapters.map { |a| adapter_json(a) },
        }
      end

      # GET /admin/imports/:id
      def show
        render_page "Escalated/Admin/Imports/Show", {
          job:      job_json(@job),
          adapters: import_service.available_adapters.map { |a| adapter_json(a) },
        }
      end

      # POST /admin/imports
      def create
        job = Escalated::ImportJob.create!(
          platform:       params.require(:platform),
          status:         "pending",
          credentials:    params[:credentials]&.to_unsafe_h || {},
          field_mappings: params[:field_mappings]&.to_unsafe_h || {},
          progress:       {},
          error_log:      [],
        )

        redirect_to escalated.admin_import_path(job),
                    notice: I18n.t("escalated.import.created")
      rescue ActionController::ParameterMissing => e
        redirect_to escalated.admin_imports_path,
                    alert: e.message
      end

      # POST /admin/imports/:id/start
      def start
        unless @job.status == "pending"
          return redirect_to escalated.admin_import_path(@job),
                             alert: I18n.t("escalated.import.already_started")
        end

        @job.transition_to!("authenticating")

        if import_service.test_connection(@job)
          @job.transition_to!("mapping")
          @job.transition_to!("importing")
        else
          @job.transition_to!("failed")
          return redirect_to escalated.admin_import_path(@job),
                             alert: I18n.t("escalated.import.connection_failed")
        end

        run_import_in_background(@job)

        redirect_to escalated.admin_import_path(@job),
                    notice: I18n.t("escalated.import.started")
      rescue ArgumentError, RuntimeError => e
        redirect_to escalated.admin_import_path(@job), alert: e.message
      end

      # POST /admin/imports/:id/pause
      def pause
        unless @job.status == "importing"
          return redirect_to escalated.admin_import_path(@job),
                             alert: I18n.t("escalated.import.cannot_pause")
        end

        @job.update!(status: "paused")

        redirect_to escalated.admin_import_path(@job),
                    notice: I18n.t("escalated.import.paused")
      end

      # POST /admin/imports/:id/resume
      def resume
        unless @job.resumable?
          return redirect_to escalated.admin_import_path(@job),
                             alert: I18n.t("escalated.import.not_resumable")
        end

        @job.transition_to!("importing")
        run_import_in_background(@job)

        redirect_to escalated.admin_import_path(@job),
                    notice: I18n.t("escalated.import.resumed")
      rescue ArgumentError, RuntimeError => e
        redirect_to escalated.admin_import_path(@job), alert: e.message
      end

      # DELETE /admin/imports/:id
      def destroy
        @job.destroy!
        redirect_to escalated.admin_imports_path,
                    notice: I18n.t("escalated.import.deleted")
      end

      # GET /admin/imports/:id/source_maps
      # Returns a JSON download of the source ID mapping for this job.
      def source_maps
        set_import_job
        maps = @job.source_maps.order(:entity_type, :source_id)

        respond_to do |format|
          format.json do
            send_data(
              JSON.pretty_generate(maps.map { |m|
                {
                  entity_type:  m.entity_type,
                  source_id:    m.source_id,
                  escalated_id: m.escalated_id,
                  created_at:   m.created_at&.iso8601,
                }
              }),
              filename:    "import_#{@job.id}_source_maps.json",
              type:        "application/json",
              disposition: "attachment",
            )
          end
        end
      end

      private

      def set_import_job
        @job = Escalated::ImportJob.find(params[:id])
      end

      def import_service
        @import_service ||= Escalated::Services::ImportService.new
      end

      # Runs the import in a background thread so the HTTP response can return
      # immediately. In production you would replace this with a proper job queue
      # (Sidekiq, GoodJob, etc.) via the "import.run_async" hook.
      def run_import_in_background(job)
        if Escalated.hooks.has_action?("import.run_async")
          Escalated.hooks.do_action("import.run_async", job)
        else
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              import_service.run(job)
            rescue StandardError => e
              Rails.logger.error("[Escalated::Import] Job #{job.id} failed: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
              job.update(status: "failed") rescue nil
            end
          end
        end
      end

      def job_json(job)
        {
          id:             job.id,
          platform:       job.platform,
          status:         job.status,
          progress:       job.progress || {},
          error_count:    (job.error_log || []).size,
          resumable:      job.resumable?,
          started_at:     job.started_at&.iso8601,
          completed_at:   job.completed_at&.iso8601,
          created_at:     job.created_at&.iso8601,
          updated_at:     job.updated_at&.iso8601,
        }
      end

      def adapter_json(adapter)
        {
          name:              adapter.name,
          display_name:      adapter.display_name,
          credential_fields: adapter.credential_fields,
          entity_types:      adapter.entity_types,
        }
      end
    end
  end
end
