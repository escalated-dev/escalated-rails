module Escalated
  class Reply < ApplicationRecord
    self.table_name = Escalated.table_name("replies")

    belongs_to :ticket, class_name: "Escalated::Ticket"
    belongs_to :author, polymorphic: true
    has_many :attachments, as: :attachable, dependent: :destroy, class_name: "Escalated::Attachment"

    validates :body, presence: true

    scope :public_replies, -> { where(is_internal: false) }
    scope :internal_notes, -> { where(is_internal: true) }
    scope :system_messages, -> { where(is_system: true) }
    scope :pinned, -> { where(is_pinned: true) }
    scope :chronological, -> { order(created_at: :asc) }
    scope :reverse_chronological, -> { order(created_at: :desc) }

    after_create :touch_ticket

    def public?
      !is_internal
    end

    def internal?
      is_internal
    end

    def system?
      is_system
    end

    def pinned?
      is_pinned
    end

    private

    def touch_ticket
      ticket.touch
    end
  end
end
