# frozen_string_literal: true

module Escalated
  module Support
    # Escalated's admin menu as data, so a host can list it in its own sidebar
    # (ADR 2026-11-05-embeddable-admin). Shared as `escalated.navigation` while
    # the admin is embedded, and available as Escalated.admin_navigation (and
    # the escalated_admin_navigation view helper) for server-rendered layouts.
    #
    # Filtered server-side so a host sidebar never links to a screen that
    # would refuse the user or answer 404: the admin gate (unless the host
    # replaced it), screens that are not routed, feature switches and, while
    # roles & permissions is on, each screen's permission. Plugin admin menu
    # items are merged in.
    module AdminNavigation
      # key (also the icon key), label, frontend route name, position, the
      # controller#action the screen is served by, and the switch it needs.
      # Labels and positions match the standalone admin sidebar.
      ITEMS = [
        ['reports', 'Reports', 'escalated.admin.reports', 10, 'reports#index'],
        ['tickets', 'Tickets', 'escalated.admin.tickets.index', 20, 'tickets#index'],
        ['departments', 'Departments', 'escalated.admin.departments.index', 30, 'departments#index'],
        ['sla-policies', 'SLA Policies', 'escalated.admin.sla-policies.index', 40, 'sla_policies#index'],
        ['knowledge-base', 'Knowledge Base', 'escalated.admin.kb-articles.index', 45, 'articles#index'],
        ['escalation-rules', 'Escalation Rules', 'escalated.admin.escalation-rules.index', 50,
         'escalation_rules#index'],
        ['workflows', 'Workflows', 'escalated.admin.workflows.index', 53, 'workflows#index'],
        ['automations', 'Automations', 'escalated.admin.automations.index', 53.5, 'automations#index'],
        ['webhooks', 'Webhooks', 'escalated.admin.webhooks.index', 54, 'webhooks#index'],
        ['tags', 'Tags', 'escalated.admin.tags.index', 60, 'tags#index'],
        ['custom-fields', 'Custom Fields', 'escalated.admin.custom-fields.index', 62, 'custom_fields#index'],
        ['statuses', 'Statuses', 'escalated.admin.statuses.index', 64, 'statuses#index'],
        ['canned-responses', 'Canned Responses', 'escalated.admin.canned-responses.index', 70,
         'canned_responses#index'],
        ['macros', 'Macros', 'escalated.admin.macros.index', 80, 'macros#index'],
        # No frontend route name in this port: a URL only, at the standalone
        # admin (the newsletter admin does not move).
        ['newsletters', 'Newsletters', nil, 81, 'newsletters#index', :newsletters],
        ['skills', 'Skills', 'escalated.admin.skills.index', 82, 'skills#index'],
        ['users', 'Users', 'escalated.admin.users.index', 83, 'users#index'],
        ['roles', 'Roles', 'escalated.admin.roles.index', 84, 'roles#index', :roles_permissions],
        ['capacity', 'Capacity', 'escalated.admin.capacity.index', 85, 'capacity#index'],
        ['business-hours', 'Business Hours', 'escalated.admin.business-hours.index', 86, 'business_hours#index'],
        ['audit-log', 'Audit Log', 'escalated.admin.audit-log', 88, 'audit_logs#index'],
        ['api-tokens', 'API Tokens', 'escalated.admin.api-tokens.index', 90, 'api_tokens#index', :api],
        ['custom-objects', 'Custom Objects', 'escalated.admin.custom-objects.index', 92, 'custom_objects#index'],
        ['plugins', 'Plugins', 'escalated.admin.plugins.index', 95, 'plugins#index', :plugins],
        ['import', 'Import', 'escalated.admin.import.index', 97, 'imports#index'],
        ['settings', 'Settings', 'escalated.admin.settings', 100, 'settings#index']
      ].freeze

      module_function

      # @param user [Object, nil] the signed-in user
      # @param request [ActionDispatch::Request, nil] marks the active item
      # @param path [String, nil] the current path, instead of +request+
      # @return [Array<Hash>]
      def for(user, request = nil, path: nil)
        return [] if user.nil?
        return [] unless EmbedConfig.replace_admin_gate? || admin?(user)

        current = normalize(path || request&.path || '')
        granted = AccessFeatures.roles_permissions? ? Escalated::AccessControl.permission_slugs(user.id) : nil
        routed = routed_endpoints
        routes = Escalated::RouteList.routes

        items = ITEMS.filter_map do |key, label, route, position, endpoint, feature|
          next unless feature_on?(feature)

          controller, action = endpoint.split('#')
          controller = "escalated/admin/#{controller}"
          next unless routed.include?("#{controller}##{action}")
          next unless granted.nil? || permitted?(controller, action, granted)

          url = route ? "/#{routes.dig(route, :uri)}" : standalone_url(endpoint)
          item(key, label, route, url, position, current)
        end

        stable_sort(items + plugin_items(user, granted, current))
      end

      def admin?(user)
        user.respond_to?(:escalated_admin?) && user.escalated_admin? == true
      end

      def feature_on?(feature)
        case feature
        when :newsletters then Escalated.configuration.enable_newsletters?
        when :roles_permissions then AccessFeatures.roles_permissions?
        when :api then Escalated.configuration.api_enabled == true
        when :plugins then Escalated.configuration.plugins_enabled?
        else true
        end
      end

      def permitted?(controller, action, granted)
        required = RoutePermissions.required_for(controller, action, {})
        !required.nil? && (required - granted).empty?
      end

      # Every controller#action the engine routes, as drawn now.
      def routed_endpoints
        Escalated::Engine.routes.routes.filter_map do |route|
          controller = route.defaults[:controller]
          "#{controller}##{route.defaults[:action]}" if controller
        end.to_set
      end

      def standalone_url(endpoint)
        "/#{[EmbedConfig.route_prefix, 'admin', endpoint.split('#').first].reject(&:empty?).join('/')}"
      end

      # Plugin menu items for the admin section, already filtered by the
      # plugin contract (Escalated::Services::PluginUIService).
      def plugin_items(user, granted, current)
        menu = Escalated.plugin_ui.shared_extensions(admin: true, permissions: granted || ['*'], viewer: user)
        Array(menu[:menuItems]).select { |entry| entry[:section].to_s == 'admin' }.each_with_index
                               .filter_map do |entry, index|
          url = entry[:route].to_s
          next if url.empty?

          plugin_item(entry, index, url, current)
        end
      rescue StandardError => e
        Rails.logger.warn("[Escalated] plugin admin menu items left out of the navigation: #{e.message}")
        []
      end

      def plugin_item(entry, index, url, current)
        item("plugin:#{entry[:plugin] || 'native'}:#{index}", entry[:label].to_s, nil, url,
             entry[:position] || 100, current).merge(
               icon: entry[:icon].is_a?(String) ? entry[:icon] : nil,
               badge: entry[:badge],
               plugin: entry[:plugin],
               children: Array(entry[:submenu]).map do |child|
                 child = child.to_h.symbolize_keys
                 { label: child[:label].to_s, url: (child[:url] || child[:route]).to_s, icon: child[:icon] }
               end
             )
      end

      # A core item; its icon key is its key. Plugin items override the icon.
      def item(key, label, route, url, position, current)
        target = normalize(url.split('?').first)
        {
          key: key,
          label: label,
          route: route,
          url: url,
          icon: key,
          position: position,
          active: current == target || current.start_with?("#{target}/"),
          badge: nil,
          plugin: nil,
          children: []
        }
      end

      def normalize(path)
        path = "/#{path.to_s.delete_prefix('/')}"
        path.length > 1 ? path.delete_suffix('/') : path
      end

      # By position, keeping the listed order between equal positions.
      def stable_sort(items)
        items.each_with_index.sort_by { |entry, index| [entry[:position].to_f, index] }.map(&:first)
      end
    end
  end
end
