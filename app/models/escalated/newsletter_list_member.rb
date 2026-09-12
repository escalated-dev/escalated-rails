# frozen_string_literal: true

module Escalated
  class NewsletterListMember < ApplicationRecord
    self.table_name = Escalated.table_name('newsletter_list_members')

    belongs_to :list, class_name: 'Escalated::NewsletterList'
    belongs_to :contact, class_name: 'Escalated::Contact'

    # Carried here rather than as a column default: Rails creates added_at as
    # datetime(6) on MySQL, where a CURRENT_TIMESTAMP default does not match
    # that precision and the column is rejected outright.
    before_validation :stamp_added_at, on: :create

    def stamp_added_at
      self.added_at ||= Time.current
    end
    private :stamp_added_at
  end
end
