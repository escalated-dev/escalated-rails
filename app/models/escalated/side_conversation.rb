module Escalated
  class SideConversation < ApplicationRecord
    self.table_name = Escalated.table_name("side_conversations")

    belongs_to :ticket, class_name: "Escalated::Ticket"
    belongs_to :created_by, class_name: Escalated.configuration.user_class, optional: true
    has_many :replies, class_name: "Escalated::SideConversationReply", dependent: :destroy

    scope :open, -> { where(status: "open") }

    def to_s
      "Side conversation: #{subject}"
    end
  end
end
