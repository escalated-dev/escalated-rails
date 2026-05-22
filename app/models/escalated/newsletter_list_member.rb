# frozen_string_literal: true

module Escalated
  class NewsletterListMember < ApplicationRecord
    self.table_name = Escalated.table_name('newsletter_list_members')

    belongs_to :list, class_name: 'Escalated::NewsletterList'
    belongs_to :contact, class_name: 'Escalated::Contact'
  end
end
