# frozen_string_literal: true

module Escalated
  # First-class identity for guest requesters. Deduped by email
  # (unique index, case-insensitive). Links to a host-app user via
  # `user_id` once the guest accepts a signup invite.
  #
  # Coexists with the inline guest_* columns on Ticket for one
  # release; the backfill migration populates `contact_id` for
  # existing rows. New code should write via Contact.
  class Contact < ApplicationRecord
    self.table_name = Escalated.table_name('contacts')

    has_many :tickets, class_name: 'Escalated::Ticket', foreign_key: :contact_id,
                       dependent: :nullify

    validates :email, presence: true, uniqueness: { case_sensitive: false }

    before_validation :normalize_email

    class << self
      def find_or_create_by_email(email, name = nil)
        normalized = email.to_s.strip.downcase
        existing = find_by(email: normalized)
        if existing
          if existing.name.blank? && name.present?
            existing.update!(name: name)
          end
          return existing
        end
        create!(email: normalized, name: name, user_id: nil, metadata: {})
      end
    end

    def link_to_user!(user_id)
      update!(user_id: user_id)
      self
    end

    # Link to a host-app user and back-stamp requester_* on all
    # prior tickets owned by this contact.
    def promote_to_user!(user_id, user_type = 'User')
      link_to_user!(user_id)
      Escalated::Ticket.where(contact_id: id)
                      .update_all(requester_id: user_id, requester_type: user_type)
      self
    end

    private

    def normalize_email
      self.email = email.to_s.strip.downcase if email.present?
    end
  end
end
