# frozen_string_literal: true

module Escalated
  class TicketLink < ApplicationRecord
    self.table_name = Escalated.table_name('ticket_links')

    LINK_TYPES = %w[problem_incident parent_child related].freeze

    belongs_to :parent_ticket, class_name: 'Escalated::Ticket'
    belongs_to :child_ticket, class_name: 'Escalated::Ticket'

    validates :link_type, presence: true, inclusion: { in: LINK_TYPES }
    validates :parent_ticket_id, uniqueness: { scope: %i[child_ticket_id link_type] }
  end
end
