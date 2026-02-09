module Escalated
  class PollImapJob < ActiveJob::Base
    queue_as :escalated

    # Poll the configured IMAP mailbox for unread messages and process them
    # as inbound emails.
    #
    # This job should be scheduled periodically (e.g., every 2-5 minutes)
    # via a cron scheduler like `whenever`, `sidekiq-cron`, or `good_job`.
    #
    # Example with sidekiq-cron:
    #   Sidekiq::Cron::Job.create(
    #     name: "Poll IMAP for inbound emails",
    #     cron: "*/5 * * * *",
    #     class: "Escalated::PollImapJob"
    #   )
    def perform
      unless Escalated.configuration.inbound_email_enabled
        Rails.logger.debug("[Escalated::PollImapJob] Inbound email is disabled, skipping")
        return
      end

      unless Escalated.configuration.inbound_email_adapter.to_s == "imap"
        Rails.logger.debug("[Escalated::PollImapJob] IMAP adapter not configured, skipping")
        return
      end

      unless imap_configured?
        Rails.logger.warn("[Escalated::PollImapJob] IMAP credentials not configured")
        return
      end

      Rails.logger.info("[Escalated::PollImapJob] Polling IMAP mailbox...")

      adapter = Escalated::Mail::Adapters::ImapAdapter.new
      messages = adapter.fetch_messages

      Rails.logger.info("[Escalated::PollImapJob] Found #{messages.size} unread messages")

      processed = 0
      failed = 0

      messages.each do |message|
        result = Services::InboundEmailService.process(message, adapter_name: "imap")

        if result&.processed?
          processed += 1
        else
          failed += 1
        end
      rescue StandardError => e
        failed += 1
        Rails.logger.error(
          "[Escalated::PollImapJob] Failed to process message from #{message.from_email}: #{e.message}"
        )
      end

      Rails.logger.info(
        "[Escalated::PollImapJob] Completed: #{processed} processed, #{failed} failed out of #{messages.size} total"
      )

      { total: messages.size, processed: processed, failed: failed }
    end

    private

    def imap_configured?
      config = Escalated.configuration
      config.imap_host.present? &&
        config.imap_username.present? &&
        config.imap_password.present?
    end
  end
end
