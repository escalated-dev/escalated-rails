# frozen_string_literal: true

module Escalated
  module Services
    # The retention settings of Admin/Settings/DataRetention, and what they
    # purge (escalated-laravel's `escalated:purge-expired` command).
    #
    # Laravel soft-deletes closed tickets and removes them for good 30 days
    # later. Tickets here have no soft delete, so a closed ticket past its
    # retention is destroyed outright, with everything that hangs off it, the
    # way the admin bulk delete destroys one. Every setting defaults to
    # "never", so until an admin picks a period nothing is purged.
    class DataRetentionService
      DAYS = {
        'never' => nil,
        '90_days' => 90,
        '180_days' => 180,
        '365_days' => 365,
        '1_year' => 365,
        '2_years' => 730,
        '3_years' => 1095,
        '5_years' => 1825
      }.freeze

      TICKET_AND_ATTACHMENT_PERIODS = %w[never 1_year 2_years 3_years 5_years].freeze
      AUDIT_LOG_PERIODS = %w[never 90_days 180_days 365_days].freeze

      SETTINGS = {
        'retention_closed_tickets' => TICKET_AND_ATTACHMENT_PERIODS,
        'retention_attachments' => TICKET_AND_ATTACHMENT_PERIODS,
        'retention_audit_logs' => AUDIT_LOG_PERIODS
      }.freeze

      GDPR_SETTING = 'retention_user_data_gdpr'

      def settings
        SETTINGS.keys.index_with { |key| period(key) }
                .merge(GDPR_SETTING => Escalated::EscalatedSetting.get_bool(GDPR_SETTING))
      end

      # How many rows a purge would remove now. Never raises: the screen shows
      # zeros rather than failing over a count.
      def preview
        { tickets: closed_tickets.count, attachments: attachments.count, audit_logs: audit_logs.count }
      rescue StandardError => e
        Rails.logger.warn("[Escalated::DataRetentionService] purge preview failed: #{e.message}")
        { tickets: 0, attachments: 0, audit_logs: 0 }
      end

      # Remove what the settings say has expired, plus expired guest
      # verification codes. Returns the count of each found; a dry run only
      # counts.
      def purge(dry_run: false)
        counts = {
          tickets: closed_tickets.count,
          attachments: attachments.count,
          audit_logs: audit_logs.count,
          guest_verifications: Escalated::GuestVerification.expired.count
        }
        return counts if dry_run

        closed_tickets.find_each { |ticket| destroy_ticket(ticket) }
        attachments.find_each(&:destroy!)
        audit_logs.delete_all
        Escalated::GuestVerification.expired.delete_all

        counts
      end

      def closed_tickets
        cutoff = cutoff_for('retention_closed_tickets')
        return Escalated::Ticket.none unless cutoff

        Escalated::Ticket.where(status: :closed).where(closed_at: ...cutoff)
      end

      def attachments
        cutoff = cutoff_for('retention_attachments')
        return Escalated::Attachment.none unless cutoff

        Escalated::Attachment.where(created_at: ...cutoff)
      end

      def audit_logs
        cutoff = cutoff_for('retention_audit_logs')
        return Escalated::AuditLog.none unless cutoff

        Escalated::AuditLog.where(created_at: ...cutoff)
      end

      private

      def period(key)
        value = Escalated::EscalatedSetting.get(key).to_s
        SETTINGS.fetch(key).include?(value) ? value : 'never'
      end

      def cutoff_for(key)
        days = DAYS[period(key)]
        days&.days&.ago
      end

      # The ticket's own associations are destroyed with it. Workflow logs and
      # pending delayed actions reference it without a dependent rule, and an
      # inbound email keeps its record of having arrived, so those are cleared
      # first or the foreign keys would refuse the delete.
      def destroy_ticket(ticket)
        Escalated::Ticket.transaction do
          Escalated::WorkflowLog.where(ticket_id: ticket.id).delete_all
          Escalated::DelayedAction.where(ticket_id: ticket.id).delete_all
          Escalated::InboundEmail.where(ticket_id: ticket.id).update_all(ticket_id: nil)
          ticket.destroy!
        end
      rescue ActiveRecord::ActiveRecordError => e
        # One ticket that cannot go should not stop the rest of the purge.
        Rails.logger.error("[Escalated::DataRetentionService] could not purge ticket #{ticket.id}: #{e.message}")
      end
    end
  end
end
