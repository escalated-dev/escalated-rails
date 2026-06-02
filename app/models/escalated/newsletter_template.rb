# frozen_string_literal: true

module Escalated
  class NewsletterTemplate < ApplicationRecord
    self.table_name = Escalated.table_name('newsletter_templates')

    validates :name, presence: true
    validates :theme, presence: true
    validates :body_markdown, presence: true
  end
end
