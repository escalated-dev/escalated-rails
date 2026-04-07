# frozen_string_literal: true

namespace :escalated do
  desc 'Run time-based automations against open tickets'
  task run_automations: :environment do
    count = Escalated::AutomationRunner.new.run
    puts "Automations complete: #{count} ticket(s) affected"
  end
end
