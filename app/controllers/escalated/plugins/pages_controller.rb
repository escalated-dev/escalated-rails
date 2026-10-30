# frozen_string_literal: true

module Escalated
  module Plugins
    # An SDK plugin's admin pages: GET {prefix}/admin/plugins/{slug}/{route}
    # (domain-model/plugin-contract.md, Pages). Behind the admin guard, plus
    # the page's `capability` when it declares one (403). Renders
    # Escalated/Plugin/Page with the plugin name, the page's component and
    # layout, and the props its own GET /{component} endpoint returns ({}
    # when it has none or it fails). An inactive or unknown plugin's page, or
    # an undeclared route, is a 404.
    class PagesController < Escalated::ApplicationController
      include Escalated::Plugins::SdkPluginRequest

      before_action :require_admin!

      def show
        name, manifest = Escalated::Bridge::SdkPluginRoutes.active_plugin(params[:slug])
        page = name && Escalated::Bridge::SdkPluginRoutes.page(manifest, params[:page_route])
        return not_found unless page
        return user_not_authorized unless capability_granted?(page)

        render_page 'Escalated/Plugin/Page', {
          plugin: name,
          component: page['component'],
          layout: page['layout'].presence || 'admin',
          props: page_props(name, manifest, page['component'])
        }
      end

      private

      def page_props(name, manifest, component)
        path = "/#{component}"
        return {} unless Escalated::Bridge::SdkPluginRoutes.match(manifest['endpoints'], 'GET', path)

        props = Escalated.plugin_bridge.call_endpoint(name, 'GET', path, { query: {}, headers: {} })
        props.is_a?(Hash) ? props : {}
      rescue StandardError => e
        Rails.logger.warn("[Escalated::Plugins] #{name} page props failed: #{e.message}")
        {}
      end
    end
  end
end
