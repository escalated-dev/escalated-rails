# frozen_string_literal: true

module Escalated
  module Services
    # Service for plugins to register custom UI elements.
    #
    # Plugins use this to inject menus, dashboard widgets, and
    # slot-based components into existing Escalated pages.
    class PluginUIService
      def initialize
        @menu_items = []
        @dashboard_widgets = []
        @page_components = {}
      end

      # ================================================================
      # Menu Items
      # ================================================================

      # Register a custom menu item.
      #
      # @param item [Hash] Menu item configuration
      # @option item [String]  :label          Display label
      # @option item [String]  :route          Named route (nil for external URL)
      # @option item [String]  :url            External URL (nil for named route)
      # @option item [String]  :icon           Icon identifier (SVG path or icon name)
      # @option item [String]  :permission     Required permission (nil = visible to all)
      # @option item [Integer] :position       Sort order (lower = higher, default 100)
      # @option item [String]  :parent         Parent menu label for sub-items
      # @option item [String]  :badge          Badge text
      # @option item [Array]   :active_routes  Route names that mark this item active
      # @option item [Array]   :submenu        Array of submenu item hashes
      # @return [void]
      def add_menu_item(item)
        defaults = {
          label: 'Custom Item',
          route: nil,
          url: nil,
          icon: nil,
          permission: nil,
          position: 100,
          parent: nil,
          badge: nil,
          active_routes: [],
          submenu: []
        }

        @menu_items << defaults.merge(item)
      end

      # Register multiple menu items at once.
      #
      # @param items [Array<Hash>]
      # @return [void]
      def add_menu_items(items)
        items.each { |item| add_menu_item(item) }
      end

      # Add a submenu item to an existing parent menu item.
      #
      # @param parent_label [String] The label of the parent menu item
      # @param submenu_item [Hash]   Submenu item configuration
      # @return [void]
      def add_submenu_item(parent_label, submenu_item)
        defaults = {
          label: 'Submenu Item',
          route: nil,
          url: nil,
          icon: nil,
          permission: nil,
          active_routes: []
        }

        merged = defaults.merge(submenu_item)

        parent = @menu_items.find { |m| m[:label] == parent_label }
        return unless parent

        parent[:submenu] ||= []
        parent[:submenu] << merged
      end

      # Get all registered menu items, sorted by position.
      #
      # @return [Array<Hash>]
      def menu_items
        @menu_items.sort_by { |m| m[:position] }
      end

      # ================================================================
      # Dashboard Widgets
      # ================================================================

      # Register a dashboard widget.
      #
      # @param widget [Hash] Widget configuration
      # @option widget [String]  :id         Unique identifier
      # @option widget [String]  :title      Widget title
      # @option widget [String]  :component  Vue component name
      # @option widget [Hash]    :data       Static data passed as props
      # @option widget [Integer] :position   Sort order (default 100)
      # @option widget [String]  :width      'full', 'half', 'third', 'quarter'
      # @option widget [String]  :permission Required permission
      # @return [void]
      def add_dashboard_widget(widget)
        defaults = {
          id: "widget_#{SecureRandom.hex(4)}",
          title: 'Custom Widget',
          component: nil,
          data: {},
          position: 100,
          width: 'full',
          permission: nil
        }

        @dashboard_widgets << defaults.merge(widget)
      end

      # Get all registered dashboard widgets, sorted by position.
      #
      # @return [Array<Hash>]
      def dashboard_widgets
        @dashboard_widgets.sort_by { |w| w[:position] }
      end

      # ================================================================
      # Page Components (Slots)
      # ================================================================

      # Register a component to be injected into an existing page slot.
      #
      # @param page      [String] Page identifier (e.g. 'ticket.show', 'dashboard')
      # @param slot      [String] Slot name (e.g. 'sidebar', 'header', 'footer', 'tabs')
      # @param component [Hash]   Component configuration
      # @option component [String]  :component  Vue component name
      # @option component [String]  :plugin     Plugin slug that registered this
      # @option component [Hash]    :data       Static data passed as props
      # @option component [Integer] :position   Sort order (default 100)
      # @option component [String]  :permission Required permission
      # @return [void]
      def add_page_component(page, slot, component)
        defaults = {
          component: nil,
          plugin: nil,
          data: {},
          position: 100,
          permission: nil
        }

        @page_components[page] ||= {}
        @page_components[page][slot] ||= []
        @page_components[page][slot] << defaults.merge(component)
      end

      # Get components for a specific page and slot, sorted by position.
      #
      # @param page [String]
      # @param slot [String]
      # @return [Array<Hash>]
      def page_components(page, slot)
        components = @page_components.dig(page, slot) || []
        components.sort_by { |c| c[:position] }
      end

      # Get all components registered for a given page.
      #
      # @param page [String]
      # @return [Hash{String => Array<Hash>}]
      def all_page_components(page)
        @page_components[page] || {}
      end

      # ================================================================
      # Serialization (for Inertia shared data)
      # ================================================================

      # Serialize all plugin UI data for sharing with the frontend.
      #
      # @return [Hash]
      def to_shared_data
        {
          menu_items: menu_items,
          dashboard_widgets: dashboard_widgets,
          page_components: serialized_page_components
        }
      end

      # `escalated.plugins` for the shared screens, in the shape the frontend's
      # usePluginExtensions() reads (domain-model/plugin-contract.md):
      # menuItems, pageComponents ("page.slot" => items) and dashboardWidgets,
      # from what active Ruby plugins registered plus the SDK plugins' widget
      # and slot declarations. Items whose permission the viewer lacks are
      # left out, and admin menu items go to admins only. {} when empty.
      #
      # @param admin [Boolean] whether the viewer is an admin
      # @param permissions [Array<String>] the viewer's permission slugs
      # @return [Hash]
      def shared_extensions(admin: false, permissions: [])
        allows = ->(ability) { ability.blank? || admin || Array(permissions).include?(ability.to_s) }
        menu = shared_menu_items(admin, allows)
        widgets = shared_widgets(admin, allows)
        slots = shared_page_components(allows)
        add_sdk_extensions(widgets, slots, allows)

        return {} if menu.empty? && widgets.empty? && slots.empty?

        {
          menuItems: menu.sort_by { |m| m[:position] },
          pageComponents: slots.transform_values { |list| list.sort_by { |c| c[:position] } },
          dashboardWidgets: widgets.sort_by { |w| w[:position] }
        }
      end

      # The contract's URL-safe slug for an SDK plugin name:
      # "@escalated-dev/plugin-slack" is "escalated-dev--plugin-slack".
      def self.slug(name)
        name.to_s.delete_prefix('@').gsub('/', '--').gsub(/[^A-Za-z0-9_-]/, '-')
      end

      # ================================================================
      # Housekeeping
      # ================================================================

      # Clear all registered UI elements (useful for testing).
      #
      # @return [void]
      def clear!
        @menu_items = []
        @dashboard_widgets = []
        @page_components = {}
      end

      private

      def shared_menu_items(admin, allows)
        menu_items.filter_map do |item|
          section = (item[:section] || item[:target] || 'admin').to_s
          next if (section == 'admin' && !admin) || !allows.call(item[:permission])

          {
            label: item[:label], route: item[:url].presence || item[:route], icon: item[:icon],
            position: item[:position] || 100, section: section, plugin: item[:plugin],
            badge: item[:badge], submenu: item[:submenu] || []
          }
        end
      end

      def shared_widgets(admin, allows)
        dashboard_widgets.filter_map do |widget|
          next if (widget[:target].to_s == 'admin' && !admin) || !allows.call(widget[:permission])

          {
            id: widget[:id], title: widget[:title], component: widget[:component], plugin: widget[:plugin],
            data: widget[:data] || {}, position: widget[:position] || 100, width: widget[:width] || 'full'
          }
        end
      end

      def shared_page_components(allows)
        slots = {}
        @page_components.each do |page, by_slot|
          by_slot.each do |slot, components|
            components.each do |component|
              next unless allows.call(component[:permission])

              (slots["#{page}.#{slot}"] ||= []) << {
                plugin: component[:plugin], component: component[:component],
                data: component[:data] || {}, position: component[:position] || 100
              }
            end
          end
        end
        slots
      end

      # SDK plugins' widget and slot declarations. Their pages are not
      # mounted by this engine yet, so their menu entries are not shared.
      def add_sdk_extensions(widgets, slots, allows)
        sdk_manifests.each do |name, manifest|
          slug = self.class.slug(name)
          Array(manifest['widgets']).each do |widget|
            next if widget['component'].blank? || !allows.call(widget['capability'])

            widgets << {
              id: "#{slug}.#{widget['component']}", title: widget['label'], component: widget['component'],
              plugin: slug, position: widget['order'] || 100, width: widget['size'] || 'half'
            }
          end
          Array(manifest['components']).each do |component|
            next if component.values_at('page', 'slot', 'component').any?(&:blank?)
            next unless allows.call(component['capability'])

            (slots["#{component['page']}.#{component['slot']}"] ||= []) << {
              plugin: slug, component: component['component'],
              data: component['props'] || {}, position: component['order'] || 100
            }
          end
        end
      end

      def sdk_manifests
        bridge = Escalated.plugin_bridge
        bridge.booted? ? (bridge.manifests || {}) : {}
      rescue StandardError
        {}
      end

      def serialized_page_components
        result = {}
        @page_components.each do |page, slots|
          result[page] = {}
          slots.each do |slot, components|
            result[page][slot] = components.sort_by { |c| c[:position] }
          end
        end
        result
      end
    end
  end
end
