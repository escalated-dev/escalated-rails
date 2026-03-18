module Escalated
  module Bridge
    # Registers Rails routes dynamically from plugin manifests.
    #
    # Each plugin manifest may declare an "endpoints" array and/or a "webhooks"
    # array.  This registrar iterates the manifests and draws the corresponding
    # routes inside the Escalated engine so they are available as:
    #
    #   GET/POST /support/plugins/:plugin/api/:path  → endpoint handler
    #   POST     /support/plugins/:plugin/webhooks/:path → webhook handler
    #
    # The routes delegate to PluginEndpointsController and
    # PluginWebhooksController, which call back into the bridge.
    class RouteRegistrar
      def initialize(bridge)
        @bridge = bridge
      end

      # Register routes for all manifests.
      #
      # @param manifests [Hash{String => Hash}]  plugin_name → manifest hash
      def register_all(manifests)
        manifests.each do |plugin_name, manifest|
          register_plugin(plugin_name, manifest)
        end
      end

      private

      # Draw routes for a single plugin manifest.
      #
      # @param plugin_name [String]
      # @param manifest    [Hash]
      def register_plugin(plugin_name, manifest)
        endpoints = Array(manifest["endpoints"])
        webhooks  = Array(manifest["webhooks"])

        return if endpoints.empty? && webhooks.empty?

        safe_plugin = plugin_name.gsub(/[^a-z0-9_\-]/i, "")

        Escalated::Engine.routes.draw do
          scope "plugins/#{safe_plugin}" do
            # Data endpoints (authenticated, goes through bridge)
            endpoints.each do |ep|
              http_method = (ep["method"] || "get").downcase.to_sym
              ep_path     = ep["path"].to_s.sub(%r{\A/}, "")

              public_send(http_method, "api/#{ep_path}",
                to:   "escalated/plugins/endpoints#handle",
                defaults: { plugin: plugin_name, endpoint_path: ep_path })
            end

            # Webhook routes (no CSRF, verified by adapter)
            webhooks.each do |wh|
              http_method = (wh["method"] || "post").downcase.to_sym
              wh_path     = wh["path"].to_s.sub(%r{\A/}, "")

              public_send(http_method, "webhooks/#{wh_path}",
                to:   "escalated/plugins/webhooks#handle",
                defaults: { plugin: plugin_name, webhook_path: wh_path })
            end
          end
        end

        Rails.logger.info(
          "[Escalated::Bridge] Registered routes for plugin '#{plugin_name}': " \
          "#{endpoints.size} endpoint(s), #{webhooks.size} webhook(s)"
        )
      rescue => e
        Rails.logger.error(
          "[Escalated::Bridge] Failed to register routes for plugin '#{plugin_name}': #{e.message}"
        )
      end
    end
  end
end
