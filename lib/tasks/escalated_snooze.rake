# frozen_string_literal: true

namespace :escalated do
  desc 'Wake snoozed tickets whose snooze time has expired'
  task wake_snoozed_tickets: :environment do
    tickets = Escalated::Ticket.snooze_expired
    count = 0

    tickets.find_each do |ticket|
      Escalated::Services::TicketService.unsnooze_ticket(ticket)
      count += 1
    end

    puts "Woke #{count} snoozed ticket(s)"
  end
end
