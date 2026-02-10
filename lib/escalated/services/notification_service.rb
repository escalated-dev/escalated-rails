require "net/http"
require "json"
require "uri"

module Escalated
  module Services
    class NotificationService
      class << self
        def dispatch(event, payload = {})
          send_webhook(event, payload) if webhook_configured?
          notify_followers(event, payload) if should_notify_followers?(event)
          instrument_event(event, payload)
        end

        def send_webhook(event, payload)
          return unless webhook_configured?

          webhook_payload = build_webhook_payload(event, payload)

          Thread.new do
            begin
              uri = URI.parse(Escalated.configuration.webhook_url)
              http = Net::HTTP.new(uri.host, uri.port)
              http.use_ssl = uri.scheme == "https"
              http.open_timeout = 10
              http.read_timeout = 10

              request = Net::HTTP::Post.new(uri.path)
              request["Content-Type"] = "application/json"
              request["User-Agent"] = "Escalated-Webhook/0.1.0"
              request["X-Escalated-Event"] = event.to_s
              request["X-Escalated-Signature"] = compute_signature(webhook_payload)
              request.body = webhook_payload.to_json

              response = http.request(request)

              unless response.is_a?(Net::HTTPSuccess)
                Rails.logger.warn(
                  "[Escalated::NotificationService] Webhook returned #{response.code} for event #{event}"
                )
              end
            rescue StandardError => e
              Rails.logger.error(
                "[Escalated::NotificationService] Webhook failed for event #{event}: #{e.message}"
              )
            end
          end
        end

        private

        def webhook_configured?
          Escalated.configuration.webhook_url.present?
        end

        def build_webhook_payload(event, payload)
          data = {
            event: event.to_s,
            timestamp: Time.current.iso8601,
            data: {}
          }

          if payload[:ticket]
            ticket = payload[:ticket]
            data[:data][:ticket] = {
              id: ticket.respond_to?(:id) ? ticket.id : nil,
              reference: ticket.respond_to?(:reference) ? ticket.reference : nil,
              subject: ticket.respond_to?(:subject) ? ticket.subject : nil,
              status: ticket.respond_to?(:status) ? ticket.status : nil,
              priority: ticket.respond_to?(:priority) ? ticket.priority : nil
            }
          end

          if payload[:reply]
            reply = payload[:reply]
            data[:data][:reply] = {
              id: reply.respond_to?(:id) ? reply.id : nil,
              is_internal: reply.respond_to?(:is_internal) ? reply.is_internal : nil
            }
          end

          if payload[:agent]
            agent = payload[:agent]
            data[:data][:agent] = {
              id: agent.respond_to?(:id) ? agent.id : nil,
              email: agent.respond_to?(:email) ? agent.email : nil
            }
          end

          # Include any extra scalar values
          payload.each do |key, value|
            next if [:ticket, :reply, :agent, :rule, :recipients].include?(key)
            data[:data][key] = value if value.is_a?(String) || value.is_a?(Symbol) || value.is_a?(Numeric) || value.is_a?(TrueClass) || value.is_a?(FalseClass)
          end

          data
        end

        def compute_signature(payload)
          key = Escalated.configuration.hosted_api_key || "escalated-webhook-secret"
          OpenSSL::HMAC.hexdigest("SHA256", key, payload.to_json)
        end

        def should_notify_followers?(event)
          [:reply_added, :status_changed, :ticket_assigned, :priority_changed].include?(event)
        end

        def notify_followers(event, payload)
          ticket = payload[:ticket]
          return unless ticket.respond_to?(:followers)

          reply = payload[:reply]
          actor = payload[:agent]

          ticket.followers.each do |follower|
            # Skip the actor (person who performed the action)
            next if actor && follower.id == actor.id
            # Skip the reply author
            next if reply && reply.respond_to?(:author) && reply.author == follower
            # Skip the assignee (they already get notified separately)
            next if ticket.respond_to?(:assigned_to) && ticket.assigned_to == follower.id
            # Skip the requester (they already get notified separately)
            next if ticket.respond_to?(:requester) && ticket.requester == follower

            if Escalated.configuration.notification_channels.include?(:email)
              begin
                case event
                when :reply_added
                  Escalated::TicketMailer.reply_received(ticket, reply).deliver_later
                when :status_changed
                  Escalated::TicketMailer.status_changed(ticket).deliver_later
                when :ticket_assigned
                  Escalated::TicketMailer.ticket_assigned(ticket).deliver_later
                when :priority_changed
                  # Priority change notification to followers
                  Escalated::TicketMailer.status_changed(ticket).deliver_later
                end
              rescue StandardError => e
                Rails.logger.warn(
                  "[Escalated::NotificationService] Follower notification failed for #{follower.id}: #{e.message}"
                )
              end
            end
          end
        rescue StandardError => e
          Rails.logger.warn(
            "[Escalated::NotificationService] Follower notification dispatch failed: #{e.message}"
          )
        end

        def instrument_event(event, payload)
          ActiveSupport::Notifications.instrument("escalated.notification.#{event}", payload)
        end
      end
    end
  end
end
