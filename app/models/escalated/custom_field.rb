# frozen_string_literal: true

module Escalated
  class CustomField < ApplicationRecord
    self.table_name = Escalated.table_name('custom_fields')

    FIELD_TYPES = %w[text textarea select multi_select checkbox date number].freeze
    CONTEXTS = %w[ticket user organization].freeze

    has_many :values, class_name: 'Escalated::CustomFieldValue', dependent: :destroy

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true

    before_validation :generate_slug, if: -> { slug.blank? }

    scope :ordered, -> { order(position: :asc) }
    scope :active, -> { where(active: true) }
    scope :for_context, ->(ctx) { where(context: ctx) }

    def to_s
      name
    end

    private

    def generate_slug
      self.slug = name.to_s.parameterize(separator: '_')
    end
  end
end
