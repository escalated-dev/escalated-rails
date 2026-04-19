# frozen_string_literal: true

require 'escalated/broadcasting'
require 'escalated/engine'
require 'escalated/configuration'
require 'escalated/manager'
require 'escalated/support/hook_manager'
require 'escalated/support/import_context'
require 'escalated/import_adapter'
require 'escalated/services/assignment_service'
require 'escalated/services/attachment_service'
require 'escalated/services/automation_runner'
require 'escalated/services/business_hours_calculator'
require 'escalated/services/capacity_service'
require 'escalated/services/chat_availability_service'
require 'escalated/services/chat_routing_service'
require 'escalated/services/chat_session_service'
require 'escalated/services/escalation_service'
require 'escalated/services/hook_registry'
require 'escalated/services/import_service'
require 'escalated/services/inbound_email_service'
require 'escalated/services/macro_service'
require 'escalated/services/notification_service'
require 'escalated/services/plugin_service'
require 'escalated/services/plugin_ui_service'
require 'escalated/services/reporting_service'
require 'escalated/services/skill_routing_service'
require 'escalated/services/sla_service'
require 'escalated/services/sso_service'
require 'escalated/services/ticket_merge_service'
require 'escalated/services/ticket_service'
require 'escalated/services/two_factor_service'
require 'escalated/services/webhook_dispatcher'
require 'escalated/ui_renderer'
require 'escalated/bridge/json_rpc_client'
require 'escalated/bridge/context_handler'
require 'escalated/bridge/route_registrar'
require 'escalated/bridge/plugin_bridge'

module Escalated
  class << self
    attr_writer :configuration, :ui_renderer

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    delegate :driver, to: :Manager

    # Global UI renderer instance.
    #
    # Defaults to InertiaRenderer when ui_enabled is true.
    # Raises RuntimeError when UI is disabled and no custom renderer is set.
    #
    # @return [Escalated::UiRenderer::Base]
    def ui_renderer
      @ui_renderer ||= if configuration.ui_enabled?
                         UiRenderer::InertiaRenderer.new
                       else
                         raise 'Escalated UI is disabled. Set ui_enabled=true or assign a custom Escalated.ui_renderer.'
                       end
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
      @ui_renderer   = nil
    end
  end
end
