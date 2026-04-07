# frozen_string_literal: true

module Escalated
  module Plugins
    # Handles incoming webhook requests for SDK plugins.
    #
    # Routes are registered dynamically by RouteRegistrar based on each plugin
    # manifest's "webhooks" array.  CSRF protection is skipped because webhook
    # callers are external services; authentication is delegated to the plugin
    # itself (it verifies signatures, shared secrets, etc. via ctx.config).
    class WebhooksController < ApplicationController
      protect_from_forgery with: :null_session

      # Handle any HTTP method forwarded to a plugin webhook.
      def handle
        plugin       = params[:plugin]
        webhook_path = params[:webhook_path] || ''
        http_method  = request.method.downcase

        bridge = Escalated.plugin_bridge
        unless bridge&.booted?
          render json: { error: 'Plugin runtime is not available' }, status: :service_unavailable
          return
        end

        result = bridge.call_webhook(
          plugin,
          http_method,
          "/#{webhook_path}",
          request_body,
          request_headers
        )

        render json: result
      rescue StandardError => e
        Rails.logger.error("[Escalated::Plugins::WebhooksController] #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end

      private

      def request_body
        body = request.body.read
        return {} if body.blank?

        JSON.parse(body)
      rescue JSON::ParserError
        {}
      end

      def request_headers
        request.headers.each_with_object({}) do |(key, value), hash|
          # Expose only HTTP_ headers (standard Rack convention)
          next unless key.start_with?('HTTP_') || key == 'CONTENT_TYPE' || key == 'CONTENT_LENGTH'

          normalized = key
                       .sub(/\AHTTP_/, '')
                       .split('_')
                       .map(&:capitalize)
                       .join('-')

          hash[normalized] = value
        end
      end
    end
  end
end
