module Escalated
  class CheckSlaJob < ActiveJob::Base
    queue_as :escalated

    def perform
      return unless Escalated.configuration.sla_enabled?

      Rails.logger.info("[Escalated::CheckSlaJob] Checking SLA breaches...")

      breached = Services::SlaService.check_breaches
      warnings = Services::SlaService.check_warnings

      Rails.logger.info(
        "[Escalated::CheckSlaJob] Found #{breached.size} breaches and #{warnings.size} warnings"
      )

      # Send warning notifications
      warnings.each do |warning|
        ticket = warning[:ticket]
        type = warning[:type]

        ActiveSupport::Notifications.instrument("escalated.sla.warning", {
          ticket: ticket,
          warning_type: type
        })
      end

      # Check if any breached tickets should be escalated
      breached.each do |ticket|
        Services::EscalationService.evaluate_ticket(ticket)
      end

      { breaches: breached.size, warnings: warnings.size }
    end
  end
end
