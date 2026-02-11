require "escalated/engine"
require "escalated/configuration"
require "escalated/manager"
require "escalated/support/hook_manager"
require "escalated/services/hook_registry"
require "escalated/services/plugin_service"
require "escalated/services/plugin_ui_service"

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

    # Reset hooks and plugin UI (useful for testing).
    #
    # @return [void]
    def reset_plugins!
      @hooks = Support::HookManager.new
      @plugin_ui = Services::PluginUIService.new
    end
  end
end
