# frozen_string_literal: true

namespace :escalated do
  desc 'Purge data past the retention set on the Data Retention settings screen (DRY_RUN=1 only counts)'
  task purge_expired: :environment do
    dry_run = ENV['DRY_RUN'].to_s.in?(%w[1 true yes])
    puts 'DRY RUN: nothing will be deleted.' if dry_run

    counts = Escalated::PurgeExpiredDataJob.perform_now(dry_run: dry_run)

    puts "Closed tickets: #{counts[:tickets]}"
    puts "Attachments: #{counts[:attachments]}"
    puts "Audit logs: #{counts[:audit_logs]}"
    puts "Expired guest verification codes: #{counts[:guest_verifications]}"
    puts dry_run ? 'Dry run complete.' : 'Purge complete.'
  end
end
