# frozen_string_literal: true

module Escalated
  module Plugins
    # What the SDK plugin page, endpoint and webhook controllers share: the
    # request as the plugin sees it, the capability check and the generic
    # failure answer (domain-model/plugin-contract.md, Endpoints and webhooks).
    module SdkPluginRequest
      extend ActiveSupport::Concern

      private

      # The path after {prefix}/{api,webhooks}/plugins/{slug}, as the manifest
      # writes it ("/items/42").
      def plugin_request_path
        "/#{params[:plugin_path]}"
      end

      def request_body
        body = request.raw_post.to_s
        return {} if body.blank?

        JSON.parse(body)
      rescue JSON::ParserError
        {}
      end

      # The request's headers, lower-case, without the browser's credentials
      # or proxy headers.
      def plugin_headers
        headers = request.headers.each_with_object({}) do |(key, value), hash|
          next unless key.start_with?('HTTP_') || %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)

          hash[key.delete_prefix('HTTP_').downcase.tr('_', '-')] = value.to_s
        end
        Escalated::Bridge::SdkPluginRoutes.strip_headers(headers)
      end

      # Whether the signed-in user holds the `capability` a manifest page or
      # endpoint declares (none declared: yes). While roles & permissions is
      # off, staff hold every permission.
      def capability_granted?(entry)
        capability = entry['capability']
        return true if capability.blank?

        granted = shared_permissions(escalated_current_user, true)
        granted.include?('*') || granted.include?(capability.to_s)
      end

      # A plugin that throws is a 500 with a generic message; the error goes
      # to the log, not the client.
      def plugin_failed(error, name)
        Rails.logger.error("[Escalated::Plugins] #{name || params[:slug]} #{request.method} " \
                           "#{plugin_request_path} failed: #{error.message}")
        render json: { error: 'Plugin request failed' }, status: :internal_server_error
      end
    end
  end
end
