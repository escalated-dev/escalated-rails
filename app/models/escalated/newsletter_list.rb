# frozen_string_literal: true

module Escalated
  # Recipient list for newsletters. Can be `static` (manually-added contacts)
  # or `dynamic` (saved filter that re-evaluates at Plan time).
  class NewsletterList < ApplicationRecord
    self.table_name = Escalated.table_name('newsletter_lists')

    KINDS = %w[static dynamic].freeze

    has_many :members, class_name: 'Escalated::NewsletterListMember',
                       foreign_key: :list_id, dependent: :destroy
    has_many :contacts, through: :members

    validates :name, presence: true
    validates :kind, presence: true, inclusion: { in: KINDS }

    scope :static_lists, -> { where(kind: 'static') }
    scope :dynamic_lists, -> { where(kind: 'dynamic') }
  end
end
