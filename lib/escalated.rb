require "escalated/engine"
require "escalated/configuration"
require "escalated/manager"
require "escalated/support/hook_manager"
require "escalated/support/import_context"
require "escalated/import_adapter"
require "escalated/services/hook_registry"
require "escalated/services/plugin_service"
require "escalated/services/plugin_ui_service"
require "escalated/services/import_service"
require "escalated/bridge/json_rpc_client"
require "escalated/bridge/context_handler"
require "escalated/bridge/route_registrar"
require "escalated/bridge/plugin_bridge"

module Escalated
  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def driver
      Manager.driver
    end

    def table_name(name)
      "#{configuration.table_prefix}#{name}"
    end

    # Global HookManager instance.
    #
    # Usage:
    #   Escalated.hooks.add_action('ticket_created') { |ticket| ... }
    #   Escalated.hooks.do_action('ticket_created', ticket)
    #   Escalated.hooks.add_filter('ticket_list_query') { |query| query.where(priority: :high) }
    #   filtered = Escalated.hooks.apply_filters('ticket_list_query', query)
    #
    # @return [Escalated::Support::HookManager]
    def hooks
      @hooks ||= Support::HookManager.new
    end

    # Global PluginUIService instance for registering UI extensions.
    #
    # Usage:
    #   Escalated.plugin_ui.add_menu_item(label: 'Reports', route: '/reports')
    #   Escalated.plugin_ui.add_dashboard_widget(title: 'Stats', component: 'StatsWidget')
    #   Escalated.plugin_ui.add_page_component('ticket.show', 'sidebar', component: 'MyWidget')
    #
    # @return [Escalated::Services::PluginUIService]
    def plugin_ui
      @plugin_ui ||= Services::PluginUIService.new
    end

    # Global PluginBridge instance.
    #
    # Provides access to the Node.js plugin runtime for SDK plugins.
    # The bridge is booted lazily — calling this before boot returns the
    # unbooted instance (safe: all public methods guard against this state).
    #
    # @return [Escalated::Bridge::PluginBridge]
    def plugin_bridge
      @plugin_bridge ||= Bridge::PluginBridge.new
    end

    # Reset hooks, plugin UI, and bridge (useful for testing).
    #
    # @return [void]
    def reset_plugins!
      @hooks         = Support::HookManager.new
      @plugin_ui     = Services::PluginUIService.new
      @plugin_bridge = Bridge::PluginBridge.new
    end
  end
end
