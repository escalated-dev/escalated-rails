# frozen_string_literal: true

module Escalated
  # Delivers one event to one admin-configured webhook, outside the request
  # that raised the event: an endpoint that is slow or down (up to three
  # attempts, ten seconds each) must not hold up creating a ticket.
  class DeliverWebhookJob < ApplicationJob
    queue_as :escalated

    def perform(webhook_id, event, payload)
      webhook = Escalated::Webhook.find_by(id: webhook_id)
      return unless webhook

      Services::WebhookDispatcher.new.send_webhook(webhook, event, payload)
    end
  end
end
