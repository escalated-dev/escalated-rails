# frozen_string_literal: true

module Escalated
  # Wakes snoozed tickets whose snooze time has passed
  # (rake escalated:wake_snoozed_tickets). Returns how many it woke.
  class WakeSnoozedTicketsJob < ApplicationJob
    queue_as :escalated

    def perform
      count = 0
      Escalated::Ticket.snooze_expired.find_each do |ticket|
        Escalated::Services::TicketService.unsnooze_ticket(ticket)
        count += 1
      end
      count
    end
  end
end
