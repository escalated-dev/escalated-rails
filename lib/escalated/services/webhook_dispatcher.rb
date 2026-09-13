# frozen_string_literal: true

require 'net/http'
require 'json'
require 'openssl'

module Escalated
  module Services
    class WebhookDispatcher
      MAX_ATTEMPTS = 3

      # The webhook event each NotificationService event is delivered as.
      # reply_added and status_changed depend on the payload; see .events_for.
      EVENTS = {
        ticket_created: 'ticket.created',
        ticket_assigned: 'ticket.assigned',
        priority_changed: 'ticket.priority_changed',
        ticket_escalated: 'ticket.escalated',
        sla_breached: 'sla.breached'
      }.freeze

      STATUS_EVENTS = {
        'resolved' => 'ticket.resolved', 'closed' => 'ticket.closed', 'reopened' => 'ticket.reopened'
      }.freeze

      # What an admin can subscribe a webhook to: exactly what .events_for
      # produces, so the form never offers an event that is not sent.
      AVAILABLE_EVENTS = %w[
        ticket.created ticket.status_changed ticket.resolved ticket.closed ticket.reopened
        ticket.assigned ticket.priority_changed ticket.escalated
        reply.created internal_note.added sla.breached
      ].freeze

      def self.events_for(event, payload)
        case event.to_sym
        when :reply_added
          reply = payload[:reply]
          [reply.respond_to?(:is_internal) && reply.is_internal ? 'internal_note.added' : 'reply.created']
        when :status_changed
          ['ticket.status_changed', STATUS_EVENTS[payload[:status].to_s]].compact
        else
          Array(EVENTS[event.to_sym])
        end
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
