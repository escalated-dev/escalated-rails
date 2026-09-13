# frozen_string_literal: true

module Escalated
  class Webhook < ApplicationRecord
    self.table_name = Escalated.table_name('webhooks')

    has_many :deliveries, class_name: 'Escalated::WebhookDelivery', dependent: :destroy

    validates :url, presence: true
    validate :url_must_be_public, if: -> { url.present? && will_save_change_to_url? }

    scope :active, -> { where(active: true) }

    def subscribed_to?(event)
      Array(events).include?(event.to_s)
    end

    def to_s
      url
    end

    private

    # Refuses an address inside the server's own network when the webhook is
    # saved. Every delivery checks again, because DNS can change after this.
    def url_must_be_public
      problem = Escalated::Support::OutboundUrl.problem(url, allow_unresolved: true)
      errors.add(:url, problem) if problem
    end
  end
end
