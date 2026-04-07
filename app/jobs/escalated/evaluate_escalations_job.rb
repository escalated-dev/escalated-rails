# frozen_string_literal: true

module Escalated
  class EvaluateEscalationsJob < ApplicationJob
    queue_as :escalated

    def perform
      Rails.logger.info('[Escalated::EvaluateEscalationsJob] Evaluating escalation rules...')

      results = Services::EscalationService.evaluate_all

      Rails.logger.info(
        "[Escalated::EvaluateEscalationsJob] Escalated #{results.size} tickets"
      )

      results.each do |result|
        Rails.logger.info(
          "[Escalated::EvaluateEscalationsJob] Ticket #{result[:ticket].reference} " \
          "matched rule '#{result[:rule].name}'"
        )
      end

      { escalated_count: results.size }
    end
  end
end
