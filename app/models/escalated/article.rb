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
    # Title or body contains the term, ignoring case on every database
    # (PostgreSQL's LIKE is case-sensitive), with `%` and `_` taken literally.
    scope :search, ->(term) { search_text(term) }
    scope :search_text, lambda { |term|
      pattern = like_pattern(term)
      where("LOWER(#{quoted_table_name}.title) LIKE ? ESCAPE '!' OR LOWER(#{quoted_table_name}.body) LIKE ? ESCAPE '!'",
            pattern, pattern)
    }
    scope :recent, -> { order(created_at: :desc) }

    # `%term%`, lower-cased, with `%`, `_` and the escape character `!` escaped.
    def self.like_pattern(term)
      "%#{sanitize_sql_like(term.to_s.downcase, '!')}%"
    end

    # Articles whose title contains the term first.
    def self.title_match_order(term)
      Arel.sql(sanitize_sql_array(
                 ["CASE WHEN LOWER(#{quoted_table_name}.title) LIKE ? ESCAPE '!' THEN 0 ELSE 1 END", like_pattern(term)]
               ))
    end

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
