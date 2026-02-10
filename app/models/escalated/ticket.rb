module Escalated
  class Ticket < ApplicationRecord
    self.table_name = Escalated.table_name("tickets")

    belongs_to :requester, polymorphic: true, optional: true
    belongs_to :assignee,
               class_name: Escalated.configuration.user_class,
               optional: true,
               foreign_key: :assigned_to
    belongs_to :department, optional: true
    belongs_to :sla_policy, optional: true
    has_many :replies, dependent: :destroy
    has_many :attachments, as: :attachable, dependent: :destroy
    has_many :activities, class_name: "Escalated::TicketActivity", dependent: :destroy
    has_and_belongs_to_many :tags,
                            join_table: Escalated.table_name("ticket_tags"),
                            class_name: "Escalated::Tag"
    has_and_belongs_to_many :followers,
                            join_table: Escalated.table_name("ticket_followers"),
                            class_name: Escalated.configuration.user_class,
                            foreign_key: :ticket_id,
                            association_foreign_key: :user_id
    has_one :satisfaction_rating, class_name: "Escalated::SatisfactionRating", dependent: :destroy
    has_many :pinned_notes, -> { where(is_internal: true, is_pinned: true) },
             class_name: "Escalated::Reply"

    enum :status, {
      open: 0,
      in_progress: 1,
      waiting_on_customer: 2,
      waiting_on_agent: 3,
      escalated: 4,
      resolved: 5,
      closed: 6,
      reopened: 7
    }

    enum :priority, {
      low: 0,
      medium: 1,
      high: 2,
      urgent: 3,
      critical: 4
    }

    validates :subject, presence: true, length: { maximum: 255 }
    validates :description, presence: true
    validates :reference, uniqueness: true, allow_nil: true

    before_create :set_reference

    # Scopes
    scope :by_open, -> { where(status: [:open, :in_progress, :waiting_on_customer, :waiting_on_agent, :escalated, :reopened]) }
    scope :unassigned, -> { where(assigned_to: nil) }
    scope :assigned_to, ->(agent_id) { where(assigned_to: agent_id) }
    scope :breached_sla, -> {
      where(sla_breached: true)
        .or(where("sla_first_response_due_at < ? AND first_response_at IS NULL", Time.current))
        .or(where("sla_resolution_due_at < ? AND resolved_at IS NULL AND status NOT IN (?)", Time.current, [5, 6]))
    }
    scope :search, ->(term) {
      where("#{table_name}.subject LIKE :term OR #{table_name}.description LIKE :term OR #{table_name}.reference LIKE :term",
            term: "%#{sanitize_sql_like(term)}%")
    }
    scope :by_priority, ->(priority) { where(priority: priority) }
    scope :by_department, ->(department_id) { where(department_id: department_id) }
    scope :created_between, ->(from, to) { where(created_at: from..to) }
    scope :recent, -> { order(created_at: :desc) }

    def self.generate_reference
      prefix = Escalated::EscalatedSetting.get("ticket_reference_prefix", "ESC")
      timestamp = Time.current.strftime("%y%m")
      sequence = SecureRandom.alphanumeric(6).upcase
      "#{prefix}-#{timestamp}-#{sequence}"
    end

    def open?
      %w[open in_progress waiting_on_customer waiting_on_agent escalated reopened].include?(status)
    end

    def sla_first_response_breached?
      return false unless sla_first_response_due_at
      return false if first_response_at

      Time.current > sla_first_response_due_at
    end

    def sla_resolution_breached?
      return false unless sla_resolution_due_at
      return false if resolved_at

      Time.current > sla_resolution_due_at
    end

    def sla_first_response_warning?
      return false unless sla_first_response_due_at
      return false if first_response_at

      warning_threshold = sla_first_response_due_at - 1.hour
      Time.current > warning_threshold && Time.current <= sla_first_response_due_at
    end

    def sla_resolution_warning?
      return false unless sla_resolution_due_at
      return false if resolved_at

      warning_threshold = sla_resolution_due_at - 2.hours
      Time.current > warning_threshold && Time.current <= sla_resolution_due_at
    end

    def time_to_first_response
      return nil unless first_response_at

      first_response_at - created_at
    end

    def time_to_resolution
      return nil unless resolved_at

      resolved_at - created_at
    end

    # Guest ticket helpers

    def guest?
      requester_type.nil? && guest_token.present?
    end

    def requester_name
      return guest_name || "Guest" if guest?

      if requester
        requester.respond_to?(:name) ? requester.name : requester.to_s
      else
        "Unknown"
      end
    end

    def requester_email
      return guest_email || "" if guest?

      requester&.respond_to?(:email) ? requester.email : ""
    end

    # Follower helpers

    def followed_by?(user_id)
      followers.where(id: user_id).exists?
    end

    def follow(user_id)
      user = Escalated.configuration.user_model.find(user_id)
      followers << user unless followed_by?(user_id)
    end

    def unfollow(user_id)
      followers.delete(Escalated.configuration.user_model.find(user_id))
    end

    private

    def set_reference
      self.reference ||= self.class.generate_reference
    end
  end
end
