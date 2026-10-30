# frozen_string_literal: true

module Escalated
  module Plugins
    # An SDK plugin's webhooks: {prefix}/webhooks/plugins/{slug}{path}
    # (domain-model/plugin-contract.md, Endpoints and webhooks). No guard and
    # no CSRF: callers are external services, and the plugin authenticates
    # the sender itself. Only active plugins answer; anything else is a 404.
    class WebhooksController < Escalated::PublicController
      include Escalated::Plugins::SdkPluginRequest

      protect_from_forgery with: :null_session

      def handle
        name, manifest = Escalated::Bridge::SdkPluginRoutes.active_plugin(params[:slug])
        webhook, path_params = name && Escalated::Bridge::SdkPluginRoutes.match(
          manifest['webhooks'], request.method, plugin_request_path
        )
        return render(json: { error: 'Not Found' }, status: :not_found) unless webhook

        result = Escalated.plugin_bridge.call_webhook(
          name, webhook['method'], webhook['path'], request_body, plugin_headers,
          { params: path_params, query: request.query_parameters.to_h }
        )

        render json: result
      rescue StandardError => e
        plugin_failed(e, name)
      end
    end
  end
end
