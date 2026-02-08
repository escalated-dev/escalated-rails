module Escalated
  class Department < ApplicationRecord
    self.table_name = Escalated.table_name("departments")

    has_many :tickets, class_name: "Escalated::Ticket", dependent: :nullify
    has_and_belongs_to_many :agents,
                            join_table: Escalated.table_name("department_agents"),
                            class_name: Escalated.configuration.user_class,
                            foreign_key: :department_id,
                            association_foreign_key: :agent_id

    belongs_to :default_sla_policy,
               class_name: "Escalated::SlaPolicy",
               optional: true

    validates :name, presence: true, uniqueness: { case_sensitive: false }
    validates :slug, presence: true, uniqueness: true
    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true

    before_validation :generate_slug

    scope :active, -> { where(is_active: true) }
    scope :ordered, -> { order(:name) }

    def active?
      is_active
    end

    def open_ticket_count
      tickets.by_open.count
    end

    def agent_count
      agents.count
    end

    private

    def generate_slug
      self.slug = name&.parameterize if slug.blank?
    end
  end
end
