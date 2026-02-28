module Escalated
  class TicketStatus < ApplicationRecord
    self.table_name = Escalated.table_name("ticket_statuses")

    CATEGORIES = %w[new open pending on_hold solved].freeze

    validates :label, presence: true
    validates :slug, presence: true, uniqueness: true

    before_validation :generate_slug, if: -> { slug.blank? }

    scope :ordered, -> { order(category: :asc, position: :asc) }
    scope :by_category, ->(cat) { where(category: cat) }

    def to_s
      label
    end

    private

    def generate_slug
      self.slug = label.to_s.parameterize(separator: "_")
    end
  end
end
