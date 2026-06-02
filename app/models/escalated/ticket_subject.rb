# frozen_string_literal: true

module Escalated
  # Join row linking a ticket to one host-app subject model.
  class TicketSubject < ApplicationRecord
    self.table_name = Escalated.table_name('ticket_subjects')

    belongs_to :ticket, class_name: 'Escalated::Ticket'
    belongs_to :subject, polymorphic: true, optional: true

    validates :subject_type, :subject_id, presence: true
    validates :subject_id, uniqueness: { scope: %i[ticket_id subject_type] }
  end
end
