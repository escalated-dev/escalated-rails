module Escalated
  class Tag < ApplicationRecord
    self.table_name = Escalated.table_name("tags")

    has_and_belongs_to_many :tickets,
                            join_table: Escalated.table_name("ticket_tags"),
                            class_name: "Escalated::Ticket"

    validates :name, presence: true, uniqueness: { case_sensitive: false }
    validates :slug, presence: true, uniqueness: true
    validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "must be a valid hex color" }, allow_nil: true

    before_validation :generate_slug

    scope :ordered, -> { order(:name) }
    scope :by_name, ->(name) { where("name LIKE ?", "%#{sanitize_sql_like(name)}%") }

    def ticket_count
      tickets.count
    end

    private

    def generate_slug
      self.slug = name&.parameterize if slug.blank?
    end
  end
end
