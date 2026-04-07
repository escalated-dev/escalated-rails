# frozen_string_literal: true

module Escalated
  module Plugins
    # Handles requests routed to SDK plugin data endpoints.
    #
    # Routes are registered dynamically by RouteRegistrar based on each
    # plugin manifest's "endpoints" array.  All requests require agent or
    # admin authentication (same middleware as the rest of the engine).
    class EndpointsController < Escalated::ApplicationController
      before_action :require_agent!

      # Handle any HTTP method forwarded to a plugin endpoint.
      def handle
        plugin = params[:plugin]
        endpoint_path = params[:endpoint_path] || ''
        http_method = request.method.downcase

        bridge = Escalated.plugin_bridge
        unless bridge&.booted?
          render json: { error: 'Plugin runtime is not available' }, status: :service_unavailable
          return
        end

        result = bridge.call_endpoint(
          plugin,
          http_method,
          "/#{endpoint_path}",
          {
            body: request_body,
            params: request.query_parameters.to_unsafe_h
          }
        )

        render json: result
      rescue StandardError => e
        Rails.logger.error("[Escalated::Plugins::EndpointsController] #{e.message}")
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
    end
  end
end
