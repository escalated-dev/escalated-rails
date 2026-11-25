# frozen_string_literal: true

namespace :escalated do
  desc 'Wake snoozed tickets whose snooze time has expired'
  task wake_snoozed_tickets: :environment do
    count = Escalated::WakeSnoozedTicketsJob.perform_now
    puts "Woke #{count} snoozed ticket(s)"
  end
end
