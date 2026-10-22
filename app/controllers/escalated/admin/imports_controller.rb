# frozen_string_literal: true

module Escalated
  module Admin
    # The admin import wizard, after escalated-laravel's Admin\ImportController:
    #
    #   Index    GET  /admin/import                       adapters, recent jobs
    #   Connect  GET  /admin/import/:platform/connect     credential form
    #            POST /admin/import/:platform/test-connection  JSON { success[, error] }
    #   Mapping  GET  /admin/import/:platform/mapping     defaults + source fields
    #   Review   POST /admin/import/:platform/review      echo of the choices, nothing written
    #            POST /admin/import/:platform/start       creates the job, queues the run
    #   Progress GET  /admin/import/progress/:job_id
    #            GET  /admin/import/status/:job_id        JSON poll
    #            POST /admin/import/{pause,resume,cancel}/:job_id
    #
    # Sources come from the "import.adapters" filter; core ships none. Tested
    # credentials are kept in the session, encrypted, until the import starts,
    # and never sent back to the browser.
    class ImportsController < Escalated::ApplicationController
      before_action :require_admin!
      before_action :set_import_job, only: %i[show start pause resume cancel destroy progress status]
      before_action :set_adapter, only: %i[connect test_connection mapping launch]

      # GET /admin/import (and the older /admin/imports)
      def index
        jobs = Escalated::ImportJob.order(created_at: :desc).limit(20)

        render_page 'Escalated/Admin/Import/Index', {
          adapters: import_service.available_adapters.map { |a| adapter_json(a) },
          jobs: jobs.map { |j| job_json(j) }
        }
      end

      # GET /admin/import/:platform/connect
      def connect
        render_page 'Escalated/Admin/Import/Connect', {
          platform: @adapter.name,
          display_name: @adapter.display_name,
          credential_fields: @adapter.credential_fields
        }
      end

      # POST /admin/import/:platform/test-connection
      def test_connection
        credentials = credentials_param
        success = @adapter.test_connection(credentials) ? true : false
        session[session_key] = Escalated::Support::ImportCredentials.encrypt(credentials) if success

        render json: { success: success }
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :unprocessable_content
      end

      # GET /admin/import/:platform/mapping
      def mapping
        credentials = session_credentials
        return redirect_to_connect unless credentials

        entity_types = @adapter.entity_types
        mappings = entity_types.index_with do |type|
          {
            defaults: @adapter.default_field_mappings(type),
            source_fields: @adapter.available_source_fields(type, credentials)
          }
        end

        render_page 'Escalated/Admin/Import/Mapping', {
          platform: @adapter.name,
          display_name: @adapter.display_name,
          entity_types: entity_types,
          mappings: mappings
        }
      end

      # POST /admin/import/:platform/review
      #
      # The dry run: shows what will be imported and how, and writes nothing.
      def review
        render_page 'Escalated/Admin/Import/Review', {
          platform: params[:platform],
          field_mappings: hash_param(:field_mappings),
          entity_types: Array(params[:entity_types]).map(&:to_s)
        }
      end

      # POST /admin/import/:platform/start
      def launch
        credentials = session_credentials
        return redirect_to_connect unless credentials

        job = Escalated::ImportJob.create!(
          user_id: current_user&.id,
          platform: @adapter.name,
          status: 'mapping',
          credentials: credentials,
          field_mappings: hash_param(:field_mappings)
        )

        # The job holds them now, encrypted.
        session.delete(session_key)

        run_import_in_background(job)

        redirect_to escalated.admin_import_progress_path(job.id)
      end

      # GET /admin/import/progress/:job_id (and the older /admin/imports/:id)
      def progress
        render_page 'Escalated/Admin/Import/Progress', { job: job_json(@job) }
      end
      alias show progress

      # GET /admin/import/status/:job_id
      def status
        render json: {
          status: @job.status,
          progress: @job.progress || {},
          error_log: (@job.error_log || []).last(50),
          started_at: @job.started_at&.iso8601,
          completed_at: @job.completed_at&.iso8601
        }
      end

      # POST /admin/import/pause/:job_id
      def pause
        @job.update!(status: 'paused') if @job.status == 'importing'

        redirect_to_progress notice: I18n.t('escalated.import.paused')
      end

      # POST /admin/import/resume/:job_id
      def resume
        if @job.resumable?
          @job.transition_to!('mapping') if @job.status == 'failed'
          run_import_in_background(@job)
        end

        redirect_to_progress notice: I18n.t('escalated.import.resumed')
      end

      # POST /admin/import/cancel/:job_id
      def cancel
        @job.update!(status: 'failed', completed_at: Time.current)
        @job.purge_credentials!

        redirect_to_progress notice: I18n.t('escalated.import.cancelled')
      end

      # POST /admin/imports -- the older one-step create, kept for existing callers.
      def create
        job = Escalated::ImportJob.create!(
          user_id: current_user&.id,
          platform: params.require(:platform),
          status: 'pending',
          credentials: hash_param(:credentials),
          field_mappings: hash_param(:field_mappings)
        )

        redirect_to escalated.admin_import_progress_path(job.id), notice: I18n.t('escalated.import.created')
      rescue ActionController::ParameterMissing => e
        redirect_to escalated.admin_import_index_path, alert: e.message
      end

      # POST /admin/imports/:id/start -- starts a job made by #create.
      def start
        return redirect_to_progress alert: I18n.t('escalated.import.already_started') unless @job.status == 'pending'

        @job.transition_to!('authenticating')

        unless import_service.test_connection(@job)
          @job.transition_to!('failed')
          return redirect_to_progress alert: I18n.t('escalated.import.connection_failed')
        end

        @job.transition_to!('mapping')
        run_import_in_background(@job)

        redirect_to_progress notice: I18n.t('escalated.import.started')
      rescue ArgumentError, RuntimeError => e
        redirect_to_progress alert: e.message
      end

      # DELETE /admin/imports/:id
      def destroy
        @job.destroy!
        redirect_to escalated.admin_import_index_path, notice: I18n.t('escalated.import.deleted')
      end

      # GET /admin/imports/:id/source_maps
      # Returns a JSON download of the source ID mapping for this job.
      def source_maps
        set_import_job
        maps = @job.source_maps.order(:entity_type, :source_id)

        respond_to do |format|
          format.json do
            send_data(
              JSON.pretty_generate(maps.map do |m|
                {
                  entity_type: m.entity_type,
                  source_id: m.source_id,
                  escalated_id: m.escalated_id,
                  created_at: m.created_at&.iso8601
                }
              end),
              filename: "import_#{@job.id}_source_maps.json",
              type: 'application/json',
              disposition: 'attachment'
            )
          end
        end
      end

      private

      def set_import_job
        @job = Escalated::ImportJob.find(params[:job_id] || params[:id])
      end

      def set_adapter
        @adapter = import_service.resolve_adapter(params[:platform].to_s)
        raise ActiveRecord::RecordNotFound, "Import adapter not found: #{params[:platform]}" unless @adapter
      end

      def import_service
        @import_service ||= Escalated::Services::ImportService.new
      end

      def session_key
        "escalated.import.#{@adapter.name}.credentials"
      end

      def session_credentials
        Escalated::Support::ImportCredentials.decrypt(session[session_key])
      end

      def redirect_to_connect
        redirect_to escalated.admin_import_connect_path(@adapter.name),
                    alert: I18n.t('escalated.import.credentials_expired')
      end

      def redirect_to_progress(flash_message)
        redirect_to escalated.admin_import_progress_path(@job.id), flash_message
      end

      def credentials_param
        hash_param(:credentials).transform_values(&:to_s)
      end

      def hash_param(key)
        value = params[key]
        return {} unless value.respond_to?(:to_unsafe_h)

        value.to_unsafe_h.to_h
      end

      # Queues the run as Escalated::RunImportJob. A host can take it over with
      # the "import.run_async" action, e.g. to route it to a dedicated queue.
      def run_import_in_background(job)
        if Escalated.hooks.has_action?('import.run_async')
          Escalated.hooks.do_action('import.run_async', job)
        else
          Escalated::RunImportJob.perform_later(job.id)
        end
      end

      # Laravel sends the job model as is. Its credentials are left out here:
      # they are a secret, and the screen never reads them.
      def job_json(job)
        {
          id: job.id,
          user_id: job.user_id,
          platform: job.platform,
          status: job.status,
          field_mappings: job.field_mappings || {},
          progress: job.progress || {},
          error_log: job.error_log || [],
          error_count: (job.error_log || []).size,
          resumable: job.resumable?,
          started_at: job.started_at&.iso8601,
          completed_at: job.completed_at&.iso8601,
          created_at: job.created_at&.iso8601,
          updated_at: job.updated_at&.iso8601
        }
      end

      def adapter_json(adapter)
        {
          name: adapter.name,
          display_name: adapter.display_name,
          credential_fields: adapter.credential_fields
        }
      end
    end
  end
end
