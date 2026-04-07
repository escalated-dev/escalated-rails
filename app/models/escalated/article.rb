# frozen_string_literal: true

module Escalated
  class Article < ApplicationRecord
    self.table_name = Escalated.table_name('articles')

    belongs_to :category, class_name: 'Escalated::ArticleCategory', optional: true
    belongs_to :author, class_name: Escalated.configuration.user_class, optional: true

    validates :title, presence: true
    validates :slug, presence: true, uniqueness: true

    scope :published, -> { where(status: 'published') }
    scope :draft, -> { where(status: 'draft') }
    scope :search, ->(term) { where('title LIKE ? OR body LIKE ?', "%#{term}%", "%#{term}%") }
    scope :recent, -> { order(created_at: :desc) }

    def increment_views!
      increment!(:view_count)
    end

    def mark_helpful!
      increment!(:helpful_count)
    end

    def mark_not_helpful!
      increment!(:not_helpful_count)
    end

    def to_s
      title
    end
  end
end
