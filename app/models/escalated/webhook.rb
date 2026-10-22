# frozen_string_literal: true

module Escalated
  class Webhook < ApplicationRecord
    include Escalated::HidesSecrets

    self.table_name = Escalated.table_name('webhooks')

    # The signing secret is used to sign deliveries and never serialized.
    # Serialization carries has_secret instead.
    hides_secrets :secret

    has_many :deliveries, class_name: 'Escalated::WebhookDelivery', dependent: :destroy

    validates :url, presence: true
    validate :url_must_be_public, if: -> { url.present? && will_save_change_to_url? }

    scope :active, -> { where(active: true) }

    before_save :canonicalize_events

    def subscribed_to?(event)
      subscribed_events.include?(Escalated::EventNames.canonical(event))
    end

    # The subscribed events with legacy names read as their canonical names.
    def subscribed_events
      Array(events).map { |name| Escalated::EventNames.canonical(name) }.uniq
    end

    def secret?
      secret.present?
    end

    def serializable_hash(options = nil)
      super.merge('has_secret' => secret?)
    end

    def to_s
      url
    end

    private

    def canonicalize_events
      self.events = subscribed_events if events.is_a?(Array)
    end

    # Refuses an address inside the server's own network when the webhook is
    # saved. Every delivery checks again, because DNS can change after this.
    def url_must_be_public
      problem = Escalated::Support::OutboundUrl.problem(url, allow_unresolved: true)
      errors.add(:url, problem) if problem
    end
  end
end
