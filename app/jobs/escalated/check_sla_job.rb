# frozen_string_literal: true

module Escalated
  class CheckSlaJob < ApplicationJob
    queue_as :escalated

    def perform
      return unless Escalated.configuration.sla_enabled?

      Rails.logger.info('[Escalated::CheckSlaJob] Checking SLA breaches...')

      breached = Services::SlaService.check_breaches
      warnings = Services::SlaService.check_warnings

      Rails.logger.info(
        "[Escalated::CheckSlaJob] Found #{breached.size} breaches and #{warnings.size} warnings"
      )

      # Send warning notifications
      warnings.each do |warning|
        ticket = warning[:ticket]
        type = warning[:type]

        # Dispatched like every other event, so it is instrumented as
        # escalated.notification.sla_warning -- the name the workflow
        # subscriber listens for. It was instrumented as escalated.sla.warning,
        # which nothing heard.
        Services::NotificationService.dispatch(:sla_warning, ticket: ticket, warning_type: type)
      end

      # Check if any breached tickets should be escalated
      breached.each do |ticket|
        Services::EscalationService.evaluate_ticket(ticket)
      end

      { breaches: breached.size, warnings: warnings.size }
    end
  end
end
