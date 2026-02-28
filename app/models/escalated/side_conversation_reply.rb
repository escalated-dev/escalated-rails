module Escalated
  class SideConversationReply < ApplicationRecord
    self.table_name = Escalated.table_name("side_conversation_replies")

    belongs_to :side_conversation, class_name: "Escalated::SideConversation"
    belongs_to :author, class_name: Escalated.configuration.user_class, optional: true

    validates :body, presence: true

    def to_s
      "Reply on #{side_conversation.subject}"
    end
  end
end
