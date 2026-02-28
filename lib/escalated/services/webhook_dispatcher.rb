require "net/http"
require "json"
require "openssl"

module Escalated
  module Services
    class WebhookDispatcher
      MAX_ATTEMPTS = 3

      def dispatch(event, payload)
        Escalated::Webhook.active.each do |webhook|
          send_webhook(webhook, event, payload) if webhook.subscribed_to?(event)
        end
      end

      def send_webhook(webhook, event, payload, attempt: 1)
        body = { event: event, payload: payload, timestamp: Time.current.iso8601 }.to_json
        headers = { "Content-Type" => "application/json", "X-Escalated-Event" => event }

        if webhook.secret.present?
          signature = OpenSSL::HMAC.hexdigest("SHA256", webhook.secret, body)
          headers["X-Escalated-Signature"] = signature
        end

        delivery = Escalated::WebhookDelivery.create!(webhook: webhook, event: event, payload: payload, attempts: attempt)

        begin
          uri = URI.parse(webhook.url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = 10
          http.read_timeout = 10
          request = Net::HTTP::Post.new(uri.path, headers)
          request.body = body
          response = http.request(request)
          delivery.update!(response_code: response.code.to_i, response_body: response.body&.first(2000), delivered_at: Time.current, attempts: attempt)
          send_webhook(webhook, event, payload, attempt: attempt + 1) if !delivery.success? && attempt < MAX_ATTEMPTS
        rescue => e
          delivery.update!(response_code: 0, response_body: e.message, attempts: attempt)
          Rails.logger.warn("Escalated webhook delivery failed: #{e.message}")
          send_webhook(webhook, event, payload, attempt: attempt + 1) if attempt < MAX_ATTEMPTS
        end
      end

      def retry_delivery(delivery)
        return unless delivery.webhook

        send_webhook(delivery.webhook, delivery.event, delivery.payload || {})
      end
    end
  end
end
