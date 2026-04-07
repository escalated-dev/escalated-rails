# frozen_string_literal: true

module Escalated
  class ArticleCategory < ApplicationRecord
    self.table_name = Escalated.table_name('article_categories')

    belongs_to :parent, class_name: 'Escalated::ArticleCategory', optional: true
    has_many :children,
             class_name: 'Escalated::ArticleCategory',
             foreign_key: :parent_id,
             dependent: :nullify
    has_many :articles, class_name: 'Escalated::Article', foreign_key: :category_id, dependent: :nullify

    scope :roots, -> { where(parent_id: nil) }
    scope :ordered, -> { order(position: :asc, name: :asc) }

    def to_s
      name
    end
  end
end
