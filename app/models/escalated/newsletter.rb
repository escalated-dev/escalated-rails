# frozen_string_literal: true

module Escalated
  class Newsletter < ApplicationRecord
    self.table_name = Escalated.table_name('newsletters')

    STATUSES = %w[draft scheduled sending sent paused failed].freeze

    belongs_to :target_list, class_name: 'Escalated::NewsletterList', foreign_key: :target_list_id
    belongs_to :template, class_name: 'Escalated::NewsletterTemplate', foreign_key: :template_id,
                          optional: true
    has_many :deliveries, class_name: 'Escalated::NewsletterDelivery',
                          foreign_key: :newsletter_id, dependent: :destroy

    validates :subject, presence: true
    validates :from_email, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }

    scope :due, -> { where(status: 'scheduled').where('scheduled_at <= ?', Time.current) }
  end
end
