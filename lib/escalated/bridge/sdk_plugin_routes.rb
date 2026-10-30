# frozen_string_literal: true

module Escalated
  module Bridge
    # Resolves an SDK plugin request (domain-model/plugin-contract.md, Pages
    # and Endpoints and webhooks). The engine draws one route each for
    #
    #   GET          {prefix}/admin/plugins/{slug}/{route}  -> plugins/pages#show
    #   {any method} {prefix}/api/plugins/{slug}{path}      -> plugins/endpoints#handle
    #   {any method} {prefix}/webhooks/plugins/{slug}{path} -> plugins/webhooks#handle
    #
    # and this finds the plugin by its slug, among active plugins only, and
    # the manifest entry the request matches, so nothing is drawn at boot and
    # activating a plugin needs no restart.
    module SdkPluginRoutes
      # Headers a plugin never sees.
      STRIPPED_HEADERS = /\A(cookie|authorization|x-xsrf-token|x-csrf-token|proxy-.*)\z/i
      HTTP_METHODS = %w[GET POST PUT PATCH DELETE OPTIONS HEAD].freeze

      module_function

      # The [name, manifest] of the active SDK plugin with this slug, or nil.
      def active_plugin(slug)
        bridge = Escalated.plugin_bridge
        return nil unless bridge&.booted?

        # Two plugins sharing a slug are a configuration error: serve neither.
        matches = (bridge.manifests || {}).select { |n, _| SdkPluginActivation.slug(n) == slug.to_s }
        return nil unless matches.size == 1

        name, manifest = matches.first
        return nil unless SdkPluginActivation.active?(name)

        [name, manifest || {}]
      end

      # The manifest entry ({'method', 'path', 'capability'}) matching the
      # request, with the values of its `:param` segments; nil when none does.
      #
      # @return [Array(Hash, Hash), nil]
      def match(entries, method, request_path)
        normalize(entries).each do |entry|
          next unless entry['method'] == method.to_s.upcase

          params = match_path(entry['path'], request_path)
          return [entry, params] if params
        end
        nil
      end

      # The page whose route is +route+, or nil. Entries without a route or a
      # component are skipped.
      def page(manifest, route)
        Array(manifest['pages']).find do |page|
          next false unless page.is_a?(Hash)

          page_route = page['route'].to_s.sub(%r{\A/+}, '')
          page_route.present? && page['component'].present? && page_route == route.to_s
        end
      end

      def strip_headers(headers)
        headers.reject { |key, _| STRIPPED_HEADERS.match?(key.to_s) }
      end

      # SDK manifests list {method, path, capability}; older ones a map keyed
      # by "METHOD /path". Accept both; drop entries with a bad method or path.
      def normalize(entries)
        list = if entries.is_a?(Hash)
                 entries.map do |signature, definition|
                   verb, path = signature.to_s.split(' ', 2)
                   (definition.is_a?(Hash) ? definition : {}).merge('method' => verb, 'path' => path)
                 end
               else
                 Array(entries).grep(Hash)
               end

        list.filter_map do |entry|
          verb = entry['method'].to_s.upcase
          path = entry['path'].to_s
          next unless HTTP_METHODS.include?(verb) && path.start_with?('/')
          next if path.match?(/[\x00-\x20\x7f?#\\]/) || path.split('/').include?('..')

          entry.merge('method' => verb, 'path' => path)
        end
      end

      def match_path(pattern, request_path)
        want = pattern.split('/', -1)
        got = request_path.to_s.split('/', -1)
        return nil unless want.size == got.size

        params = {}
        want.zip(got).each do |w, g|
          if w.start_with?(':') && w.size > 1
            return nil if g.blank?

            params[w[1..]] = g
          elsif w != g
            return nil
          end
        end
        params
      end
    end
  end
end
