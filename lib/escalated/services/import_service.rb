require "escalated/support/import_context"
require "escalated/import_adapter"

module Escalated
  module Services
    class ImportService
      # -----------------------------------------------------------------------
      # Adapter registry
      # -----------------------------------------------------------------------

      # Returns all adapters registered via the "import.adapters" filter hook.
      #
      # Adapters register themselves from a plugin initializer:
      #
      #   Escalated.hooks.add_filter("import.adapters") do |adapters|
      #     adapters + [MyPlatformAdapter.new]
      #   end
      #
      # @return [Array<#Escalated::ImportAdapter>]
      def available_adapters
        Escalated.hooks.apply_filters("import.adapters", [])
      end

      # @param platform [String]  Adapter slug, e.g. "zendesk"
      # @return [Escalated::ImportAdapter, nil]
      def resolve_adapter(platform)
        available_adapters.find { |a| a.name == platform }
      end

      # -----------------------------------------------------------------------
      # Connection test
      # -----------------------------------------------------------------------

      # @param job [Escalated::ImportJob]
      # @return [Boolean]
      # @raise [RuntimeError] if no adapter is registered for the job's platform
      def test_connection(job)
        adapter = require_adapter!(job.platform)
        adapter.test_connection(job.credentials)
      end

      # -----------------------------------------------------------------------
      # Run
      # -----------------------------------------------------------------------

      # Execute (or resume) the import for the given job.
      #
      # Called by the admin controller AND the CLI rake task so both code paths
      # share identical behaviour.
      #
      # @param job         [Escalated::ImportJob]
      # @param on_progress [Proc, nil]
      #   Optional callback invoked after each batch:
      #   ->(entity_type, progress_hash) { ... }
      #
      # @return [void]
      def run(job, on_progress: nil)
        adapter = require_adapter!(job.platform)

        # Allow resume: only transition if not already importing
        job.transition_to!("importing") unless job.status == "importing"
        job.update!(started_at: job.started_at || Time.current)

        # Let the adapter cross-reference previously imported records
        adapter.job_id = job.id if adapter.respond_to?(:job_id=)

        Support::ImportContext.suppress do
          adapter.entity_types.each do |entity_type|
            # Honour a pause requested between entity types
            job.reload
            return if job.status == "paused"

            import_entity_type(job, adapter, entity_type, on_progress: on_progress)
          end
        end

        job.reload
        return if job.status == "paused"

        job.update!(status: "completed", completed_at: Time.current)
        job.purge_credentials!

        # Let plugins react to the completed import (e.g. trigger reindex)
        Escalated.hooks.do_action("import.completed", job)
      end

      # -----------------------------------------------------------------------
      # Private helpers
      # -----------------------------------------------------------------------

      private

      def require_adapter!(platform)
        adapter = resolve_adapter(platform)

        unless adapter
          raise RuntimeError, "No import adapter found for platform '#{platform}'."
        end

        adapter
      end

      # Process all pages for a single entity type.
      def import_entity_type(job, adapter, entity_type, on_progress:)
        cursor    = job.entity_cursor(entity_type)
        processed = job.progress&.dig(entity_type, "processed") || 0
        skipped   = job.progress&.dig(entity_type, "skipped")   || 0
        failed    = job.progress&.dig(entity_type, "failed")    || 0

        loop do
          result = adapter.extract(entity_type, job.credentials, cursor)

          job.update_entity_progress(entity_type, total: result.total_count) if result.total_count

          result.records.each do |record|
            source_id = record["source_id"]

            unless source_id
              failed += 1
              next
            end

            # Skip already-imported records — supports safe resume
            if ImportSourceMap.imported?(job.id, entity_type, source_id)
              skipped += 1
              next
            end

            begin
              escalated_id = persist_record(job, entity_type, record)

              ImportSourceMap.create!(
                import_job_id: job.id,
                entity_type:   entity_type,
                source_id:     source_id,
                escalated_id:  escalated_id.to_s,
              )

              processed += 1
            rescue StandardError => e
              failed += 1
              job.append_error(entity_type, source_id, e.message)
            end
          end

          cursor = result.cursor

          job.update_entity_progress(
            entity_type,
            processed: processed,
            skipped:   skipped,
            failed:    failed,
            cursor:    cursor,
          )

          on_progress&.call(entity_type, job.progress[entity_type])

          # Honour a pause requested between batches
          job.reload
          return if job.status == "paused"

          break if result.exhausted?
        end
      end

      # Dispatch a single normalised record to the correct persistence method.
      #
      # @return [String, Integer] The Escalated internal ID of the saved record.
      def persist_record(job, entity_type, record)
        mappings = job.field_mappings&.dig(entity_type) || {}

        case entity_type
        when "agents"              then persist_agent(record, mappings)
        when "tags"                then persist_tag(record, mappings)
        when "custom_fields"       then persist_custom_field(record, mappings)
        when "contacts"            then persist_contact(record, mappings)
        when "departments"         then persist_department(record, mappings)
        when "tickets"             then persist_ticket(job, record, mappings)
        when "replies"             then persist_reply(job, record, mappings)
        when "attachments"         then persist_attachment(job, record, mappings)
        when "satisfaction_ratings" then persist_satisfaction_rating(job, record, mappings)
        else
          raise RuntimeError, "Unknown entity type: #{entity_type}"
        end
      end

      # -----------------------------------------------------------------------
      # Entity persisters
      # -----------------------------------------------------------------------

      def persist_tag(record, _mappings)
        tag = Escalated::Tag.find_or_create_by!(slug: record["name"].to_s.parameterize) do |t|
          t.name = record["name"]
        end
        tag.id
      end

      def persist_agent(record, _mappings)
        user = Escalated.configuration.user_model.find_by(email: record["email"])

        unless user
          raise RuntimeError,
                "Agent with email '#{record["email"]}' not found in host application."
        end

        user.id
      end

      def persist_contact(record, _mappings)
        user = Escalated.configuration.user_model.find_or_create_by!(email: record["email"]) do |u|
          u.name = record["name"].presence || record["email"] if u.respond_to?(:name=)
        end
        user.id
      end

      def persist_department(record, _mappings)
        dept = Escalated::Department.find_or_create_by!(slug: record["name"].to_s.parameterize) do |d|
          d.name      = record["name"]
          d.is_active = true if d.respond_to?(:is_active=)
        end
        dept.id
      end

      def persist_ticket(job, record, _mappings)
        requester_id = nil
        if record["requester_source_id"].present?
          requester_id = ImportSourceMap.resolve(job.id, "contacts", record["requester_source_id"])
        end

        assignee_id = nil
        if record["assignee_source_id"].present?
          assignee_id = ImportSourceMap.resolve(job.id, "agents", record["assignee_source_id"])
        end

        department_id = nil
        if record["department_source_id"].present?
          department_id = ImportSourceMap.resolve(job.id, "departments", record["department_source_id"])
        end

        user_model = Escalated.configuration.user_model

        ticket = Escalated::Ticket.new(
          subject:       record["title"].presence || "Imported ticket",
          description:   record["description"].presence || record["body"].presence || "",
          status:        normalise_ticket_status(record["status"]),
          priority:      normalise_ticket_priority(record["priority"]),
          assigned_to:   assignee_id,
          department_id: department_id,
          metadata:      record["metadata"] || {},
        )

        if requester_id
          ticket.requester_type = user_model.to_s
          ticket.requester_id   = requester_id
        end

        # Preserve original timestamps — skip Rails auto-timestamps
        ticket.created_at = record["created_at"] ? Time.parse(record["created_at"].to_s) : Time.current
        ticket.updated_at = record["updated_at"] ? Time.parse(record["updated_at"].to_s) : Time.current

        # Skip the normal reference generation and SLA callbacks during import
        ticket.reference ||= Escalated::Ticket.generate_reference

        ticket.save!

        # Attach tags
        if record["tag_source_ids"].present?
          tag_ids = record["tag_source_ids"].filter_map do |sid|
            ImportSourceMap.resolve(job.id, "tags", sid)
          end
          ticket.tags = Escalated::Tag.where(id: tag_ids) if tag_ids.any?
        end

        ticket.id
      end

      def persist_reply(job, record, _mappings)
        ticket_id = ImportSourceMap.resolve(job.id, "tickets", record["ticket_source_id"].to_s)

        raise RuntimeError, "Parent ticket not found for reply." unless ticket_id

        author_id   = nil
        author_type = nil

        if record["author_source_id"].present?
          author_id = ImportSourceMap.resolve(job.id, "agents", record["author_source_id"]) ||
                      ImportSourceMap.resolve(job.id, "contacts", record["author_source_id"])
          author_type = Escalated.configuration.user_model.to_s if author_id
        end

        reply = Escalated::Reply.new(
          ticket_id:   ticket_id,
          body:        record["body"].to_s,
          is_internal: record["is_internal_note"] || false,
          author_type: author_type,
          author_id:   author_id,
        )
        reply.created_at = record["created_at"] ? Time.parse(record["created_at"].to_s) : Time.current
        reply.updated_at = record["updated_at"] ? Time.parse(record["updated_at"].to_s) : Time.current
        reply.save!

        reply.id
      end

      def persist_attachment(job, record, _mappings)
        parent_type      = record["parent_type"].presence || "reply"
        parent_source_id = record["parent_source_id"].to_s

        parent_entity = parent_type == "ticket" ? "tickets" : "replies"
        parent_id     = ImportSourceMap.resolve(job.id, parent_entity, parent_source_id)

        raise RuntimeError, "Parent #{parent_type} not found for attachment." unless parent_id

        attachable_class = parent_type == "ticket" ? Escalated::Ticket : Escalated::Reply

        attachment = Escalated::Attachment.create!(
          attachable_type: attachable_class.to_s,
          attachable_id:   parent_id,
          filename:        record["filename"].presence || "unknown",
          content_type:    record["mime_type"].presence || "application/octet-stream",
          byte_size:       record["size"] || 0,
        )

        attachment.id
      end

      def persist_custom_field(record, _mappings)
        field = Escalated::CustomField.find_or_create_by!(slug: record["name"].to_s.parameterize) do |f|
          f.name    = record["name"]
          f.field_type = record["type"].presence || "text" if f.respond_to?(:field_type=)
        end
        field.id
      end

      def persist_satisfaction_rating(job, record, _mappings)
        ticket_id = ImportSourceMap.resolve(job.id, "tickets", record["ticket_source_id"].to_s)

        raise RuntimeError, "Ticket not found for satisfaction rating." unless ticket_id

        rating = Escalated::SatisfactionRating.create!(
          ticket_id:  ticket_id,
          rating:     record["rating"] || record["score"],
          comment:    record["comment"],
          created_at: record["created_at"] ? Time.parse(record["created_at"].to_s) : Time.current,
        )

        rating.id
      end

      # -----------------------------------------------------------------------
      # Normalisation helpers
      # -----------------------------------------------------------------------

      TICKET_STATUS_MAP = {
        "open"     => "open",
        "pending"  => "waiting_on_customer",
        "hold"     => "waiting_on_customer",
        "solved"   => "resolved",
        "closed"   => "closed",
        "resolved" => "resolved",
      }.freeze

      TICKET_PRIORITY_MAP = {
        "low"      => "low",
        "normal"   => "medium",
        "medium"   => "medium",
        "high"     => "high",
        "urgent"   => "urgent",
        "critical" => "critical",
      }.freeze

      def normalise_ticket_status(raw)
        TICKET_STATUS_MAP.fetch(raw.to_s.downcase, "open")
      end

      def normalise_ticket_priority(raw)
        TICKET_PRIORITY_MAP.fetch(raw.to_s.downcase, "medium")
      end
    end
  end
end
