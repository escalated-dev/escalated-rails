module Escalated
  class SatisfactionRating < ApplicationRecord
    self.table_name = Escalated.table_name("satisfaction_ratings")

    belongs_to :ticket, class_name: "Escalated::Ticket"
    belongs_to :rated_by, polymorphic: true, optional: true

    validates :rating, presence: true,
                       numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }
    validates :comment, length: { maximum: 2000 }, allow_nil: true
    validates :ticket_id, uniqueness: true

    before_create :set_created_at

    private

    def set_created_at
      self.created_at ||= Time.current
    end
  end
end
