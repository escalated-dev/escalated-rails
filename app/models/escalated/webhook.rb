# frozen_string_literal: true

module Escalated
  class Webhook < ApplicationRecord
    self.table_name = Escalated.table_name('webhooks')

    has_many :deliveries, class_name: 'Escalated::WebhookDelivery', dependent: :destroy

    validates :url, presence: true

    scope :active, -> { where(active: true) }

    def subscribed_to?(event)
      Array(events).include?(event.to_s)
    end

    def to_s
      url
    end
  end
end
