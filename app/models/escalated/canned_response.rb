module Escalated
  class CannedResponse < ApplicationRecord
    self.table_name = Escalated.table_name("canned_responses")

    belongs_to :creator,
               class_name: Escalated.configuration.user_class,
               foreign_key: :created_by

    validates :title, presence: true
    validates :body, presence: true
    validates :shortcode, uniqueness: { case_sensitive: false }, allow_nil: true

    scope :shared, -> { where(is_shared: true) }
    scope :personal, -> { where(is_shared: false) }
    scope :for_user, ->(user_id) { where(is_shared: true).or(where(created_by: user_id)) }
    scope :by_category, ->(category) { where(category: category) }
    scope :search, ->(term) {
      where("title LIKE :term OR body LIKE :term OR shortcode LIKE :term",
            term: "%#{sanitize_sql_like(term)}%")
    }
    scope :ordered, -> { order(:title) }

    def shared?
      is_shared
    end

    def personal?
      !is_shared
    end

    # Render body with variable interpolation
    # Variables: {{ticket.subject}}, {{ticket.requester_name}}, {{agent.name}}
    def render(variables = {})
      rendered = body.dup

      variables.each do |key, value|
        rendered.gsub!("{{#{key}}}", value.to_s)
      end

      # Remove any unmatched variables
      rendered.gsub!(/\{\{[^}]+\}\}/, "")
      rendered
    end
  end
end
