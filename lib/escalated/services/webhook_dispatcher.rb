# frozen_string_literal: true

require 'net/http'
require 'json'
require 'openssl'

module Escalated
  module Services
    class WebhookDispatcher
      MAX_ATTEMPTS = 3

      # What an admin can subscribe a webhook to: exactly the canonical names
      # this engine emits, so the form never offers an event that is not sent.
      AVAILABLE_EVENTS = Escalated::EventNames::EMITTED

      def self.events_for(event, payload)
        Escalated::EventNames.for_notification(event, payload)
      end

      def dispatch(event, payload)
        subscribers(event).each { |webhook| send_webhook(webhook, event, payload) }
      end

      # As #dispatch, with each delivery in its own DeliverWebhookJob.
      def dispatch_later(event, payload)
        subscribers(event).each do |webhook|
          Escalated::DeliverWebhookJob.perform_later(webhook.id, event, payload)
        end
      end

      def send_webhook(webhook, event, payload, attempt: 1)
        body = { event: event, payload: payload, timestamp: Time.current.iso8601 }.to_json
        headers = { 'Content-Type' => 'application/json', 'X-Escalated-Event' => event }

        if webhook.secret.present?
          signature = OpenSSL::HMAC.hexdigest('SHA256', webhook.secret, body)
          headers['X-Escalated-Signature'] = signature
        end

        delivery = Escalated::WebhookDelivery.create!(webhook: webhook, event: event, payload: payload,
                                                      attempts: attempt)

        begin
          response = post(webhook.url, headers, body)
          delivery.update!(response_code: response.code.to_i, response_body: response.body&.first(2000),
                           delivered_at: Time.current, attempts: attempt)
          send_webhook(webhook, event, payload, attempt: attempt + 1) if !delivery.success? && attempt < MAX_ATTEMPTS
        rescue Escalated::Support::OutboundUrl::UnsafeUrl => e
          # Not retried: asking again will not make the address safe.
          delivery.update!(response_code: 0, response_body: e.message, attempts: attempt)
          Rails.logger.warn("Escalated webhook #{webhook.id} not delivered: #{e.message}")
        rescue StandardError => e
          delivery.update!(response_code: 0, response_body: e.message, attempts: attempt)
          Rails.logger.warn("Escalated webhook delivery failed: #{e.message}")
          send_webhook(webhook, event, payload, attempt: attempt + 1) if attempt < MAX_ATTEMPTS
        end
      end

      def retry_delivery(delivery)
        return unless delivery.webhook

        send_webhook(delivery.webhook, delivery.event, delivery.payload || {})
      end

      private

      def subscribers(event)
        Escalated::Webhook.active.select { |webhook| webhook.subscribed_to?(event) }
      end

      # Connects to the address OutboundUrl checked rather than resolving the
      # name again, and never follows a redirect (Net::HTTP does not), so a 3xx
      # cannot send the request somewhere private either.
      def post(url, headers, body)
        address = Escalated::Support::OutboundUrl.public_address!(url)
        uri = URI.parse(url)

        http = Net::HTTP.new(uri.hostname, uri.port)
        http.ipaddr = address if address
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 10
        http.read_timeout = 10

        # request_uri rather than path: path drops the query string, and is
        # empty for a bare host, which Net::HTTP refuses.
        request = Net::HTTP::Post.new(uri.request_uri, headers)
        request.body = body
        http.request(request)
      end
    end
  end
end
