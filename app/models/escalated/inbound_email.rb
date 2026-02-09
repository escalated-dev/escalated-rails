module Escalated
  class InboundEmail < ApplicationRecord
    self.table_name = Escalated.table_name("inbound_emails")

    belongs_to :ticket, class_name: "Escalated::Ticket", optional: true
    belongs_to :reply, class_name: "Escalated::Reply", optional: true

    enum :status, {
      pending: "pending",
      processed: "processed",
      failed: "failed",
      spam: "spam"
    }

    validates :from_email, presence: true
    validates :to_email, presence: true
    validates :subject, presence: true
    validates :adapter, presence: true
    validates :message_id, uniqueness: true, allow_nil: true

    scope :unprocessed, -> { where(status: :pending) }
    scope :recent, -> { order(created_at: :desc) }

    def mark_processed!(ticket:, reply: nil)
      update!(
        status: :processed,
        ticket: ticket,
        reply: reply,
        processed_at: Time.current
      )
    end

    def mark_failed!(error)
      update!(
        status: :failed,
        error_message: error.to_s,
        processed_at: Time.current
      )
    end

    def mark_spam!
      update!(
        status: :spam,
        processed_at: Time.current
      )
    end

    def processed?
      status == "processed"
    end

    def duplicate?
      return false if message_id.blank?

      self.class.where(message_id: message_id)
        .where.not(id: id)
        .exists?
    end
  end
end
