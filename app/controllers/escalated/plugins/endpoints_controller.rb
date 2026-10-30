# frozen_string_literal: true

module Escalated
  module Plugins
    # An SDK plugin's data endpoints: {prefix}/api/plugins/{slug}{path}
    # (domain-model/plugin-contract.md, Endpoints and webhooks). Behind the
    # admin guard, plus the endpoint's `capability` when it declares one
    # (403). Only active plugins answer; anything else is a 404.
    class EndpointsController < Escalated::ApplicationController
      include Escalated::Plugins::SdkPluginRequest

      before_action :require_admin!

      def handle
        name, manifest = Escalated::Bridge::SdkPluginRoutes.active_plugin(params[:slug])
        endpoint, path_params = name && Escalated::Bridge::SdkPluginRoutes.match(
          manifest['endpoints'], request.method, plugin_request_path
        )
        return render(json: { error: 'Not Found' }, status: :not_found) unless endpoint
        return render(json: { error: 'Forbidden' }, status: :forbidden) unless capability_granted?(endpoint)

        result = Escalated.plugin_bridge.call_endpoint(
          name, endpoint['method'], endpoint['path'],
          { body: request_body, params: path_params, query: request.query_parameters.to_h, headers: plugin_headers }
        )

        render json: result
      rescue StandardError => e
        plugin_failed(e, name)
      end
    end
  end
end
