# frozen_string_literal: true

module Escalated
  # Time-based automations against open tickets (rake escalated:run_automations).
  class RunAutomationsJob < ApplicationJob
    queue_as :escalated

    def perform
      Escalated::Services::AutomationRunner.new.run
    end
  end
end
