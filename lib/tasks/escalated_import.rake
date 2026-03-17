namespace :escalated do
  namespace :import do
    # -------------------------------------------------------------------------
    # escalated:import:run[platform]
    #
    # Start or resume an import for the given platform.
    #
    # Usage:
    #   rails "escalated:import:run[zendesk]"
    #   rails "escalated:import:run[zendesk,JOB_UUID]"
    #
    # When a JOB_UUID is supplied the task resumes that job; otherwise the most
    # recent resumable job for that platform is chosen, or a new job is created
    # if none exists.
    # -------------------------------------------------------------------------
    desc "Run (or resume) an import for PLATFORM. Optionally supply a JOB_UUID to target a specific job."
    task :run, [:platform, :job_id] => :environment do |_t, args|
      platform = args[:platform].presence
      abort "Usage: rails \"escalated:import:run[platform]\"" unless platform

      service = Escalated::Services::ImportService.new

      adapter = service.resolve_adapter(platform)
      abort "No import adapter registered for platform '#{platform}'. " \
            "Available: #{service.available_adapters.map(&:name).join(", ").presence || "(none)"}" unless adapter

      job = if args[:job_id].present?
              Escalated::ImportJob.find(args[:job_id]).tap do |j|
                abort "Job #{j.id} is not resumable (status: #{j.status})." unless j.resumable? || j.status == "pending"
              end
            else
              # Find the latest resumable job or create a new one
              Escalated::ImportJob
                .where(platform: platform)
                .where(status: %w[paused failed])
                .order(created_at: :desc)
                .first
            end

      if job
        puts "[escalated:import] Resuming job #{job.id} (status: #{job.status}) for platform '#{platform}'..."
        job.transition_to!("importing")
      else
        puts "[escalated:import] Creating new import job for platform '#{platform}'..."
        puts "[escalated:import] Note: credentials must be set on the job before running via CLI."
        puts "[escalated:import] Create the job via the admin UI first, then resume it here."
        abort "No resumable job found for platform '#{platform}'. " \
              "Create one via the admin UI at /admin/imports."
      end

      progress_reporter = ->(entity_type, progress_data) do
        processed = progress_data["processed"] || 0
        total     = progress_data["total"]
        skipped   = progress_data["skipped"] || 0
        failed    = progress_data["failed"]  || 0
        pct       = total && total > 0 ? " (#{(processed.to_f / total * 100).round(1)}%)" : ""
        puts "[escalated:import] #{entity_type}: #{processed}/#{total || "?"}#{pct} processed, #{skipped} skipped, #{failed} failed"
      end

      begin
        service.run(job, on_progress: progress_reporter)

        job.reload
        case job.status
        when "completed"
          puts "[escalated:import] Import completed successfully."
        when "paused"
          puts "[escalated:import] Import paused. Resume with:"
          puts "  rails \"escalated:import:run[#{platform},#{job.id}]\""
        else
          puts "[escalated:import] Import ended with status: #{job.status}"
        end
      rescue StandardError => e
        abort "[escalated:import] Import failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
    end

    # -------------------------------------------------------------------------
    # escalated:import:list
    #
    # List all import jobs.
    # -------------------------------------------------------------------------
    desc "List all import jobs with their current status."
    task list: :environment do
      jobs = Escalated::ImportJob.order(created_at: :desc).limit(50)

      if jobs.empty?
        puts "No import jobs found."
        next
      end

      puts format("%-36s  %-12s  %-14s  %-20s  %-20s",
                  "ID", "Platform", "Status", "Started At", "Completed At")
      puts "-" * 110

      jobs.each do |job|
        puts format("%-36s  %-12s  %-14s  %-20s  %-20s",
                    job.id,
                    job.platform,
                    job.status,
                    job.started_at&.strftime("%Y-%m-%d %H:%M") || "-",
                    job.completed_at&.strftime("%Y-%m-%d %H:%M") || "-")
      end
    end

    # -------------------------------------------------------------------------
    # escalated:import:source_maps[job_id]
    #
    # Export source ID mappings for a job to STDOUT (JSON).
    # -------------------------------------------------------------------------
    desc "Export source ID mappings for JOB_ID as JSON to STDOUT."
    task :source_maps, [:job_id] => :environment do |_t, args|
      abort "Usage: rails \"escalated:import:source_maps[JOB_UUID]\"" unless args[:job_id].present?

      job = Escalated::ImportJob.find(args[:job_id])
      maps = job.source_maps.order(:entity_type, :source_id)

      puts JSON.pretty_generate(maps.map { |m|
        {
          entity_type:  m.entity_type,
          source_id:    m.source_id,
          escalated_id: m.escalated_id,
          created_at:   m.created_at&.iso8601,
        }
      })
    end
  end
end
