# frozen_string_literal: true

module Escalated
  # When an agent last read a ticket (ADR 2026-11-05-agent-panel-data).
  # last_read_at nil means the agent marked it unread.
  class TicketRead < ApplicationRecord
    self.table_name = Escalated.table_name('ticket_reads')

    belongs_to :ticket, class_name: 'Escalated::Ticket'
  end
end
