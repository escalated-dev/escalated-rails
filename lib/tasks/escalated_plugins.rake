# frozen_string_literal: true

namespace :escalated do
  namespace :plugins do
    desc 'Run the due cron schedules of SDK plugins (schedule every minute; AT=<ISO 8601 time> to pick the minute)'
    task cron: :environment do
      at = ENV['AT'].present? ? Time.iso8601(ENV.fetch('AT')) : Time.now.utc
      sent = Escalated::Services::PluginCron.run_due(at)
      puts "Ran #{sent} plugin cron schedule(s)"
    end
  end
end
