# frozen_string_literal: true

# Hello World Plugin for Escalated
#
# This plugin demonstrates the Escalated plugin system. It registers
# a few harmless hooks, logs activity, and injects a banner component
# on the dashboard. Delete it whenever you like!
#
# Demonstrates:
# - Action hooks (lifecycle + domain events)
# - Filter hooks (modifying data in the pipeline)
# - UI extensions (dashboard widget, page component)
# - Plugin lifecycle events (activate, deactivate, uninstall)

# ========================================
# LIFECYCLE HOOKS
# ========================================

# Runs when the plugin is activated
Escalated.hooks.add_action("plugin_activated_hello-world") do
  Rails.logger.info "[HelloWorld] Plugin activated! Ready to do... nothing useful."
end

# Runs when the plugin is deactivated
Escalated.hooks.add_action("plugin_deactivated_hello-world") do
  Rails.logger.info "[HelloWorld] Plugin deactivated. We had a good run!"
end

# Runs when the plugin is being deleted
Escalated.hooks.add_action("plugin_uninstalling_hello-world") do
  Rails.logger.info "[HelloWorld] Plugin is being deleted. Goodbye!"
end

# ========================================
# REGULAR PLUGIN CODE
# ========================================

# Log when this plugin file is loaded
Escalated.hooks.add_action("plugin_loaded") do |slug, manifest|
  if slug == "hello-world"
    Rails.logger.info "[HelloWorld] Loaded v#{manifest['version'] || 'unknown'}."

    # Register a banner component on the dashboard header slot
    Escalated.plugin_ui.add_page_component("dashboard", "header",
      component: "HelloWorldBanner",
      plugin: "hello-world",
      position: 1,
    )
  end
end

# ========================================
# EXAMPLES (uncomment to try!)
# ========================================

# Example 1: Log when tickets are created
# Escalated.hooks.add_action("ticket_created") do |ticket|
#   Rails.logger.info "[HelloWorld] A ticket was born! #{ticket.reference}"
# end

# Example 2: Add custom data to dashboard stats
# Escalated.hooks.add_filter("dashboard_stats_data") do |stats, _user|
#   stats.merge(hello_world_counter: rand(1..100))
# end

# Example 3: Add a custom menu item
# Escalated.plugin_ui.add_menu_item(
#   label: "Hello World",
#   route: "dashboard",
#   icon: "hand-wave",
#   position: 999,
# )

# Example 4: Add a dashboard widget
# Escalated.plugin_ui.add_dashboard_widget(
#   id: "hello_world_widget",
#   title: "Hello World",
#   component: "HelloWorldWidget",
#   data: { message: "Hello from the plugin system!" },
#   position: 999,
#   width: "half",
# )

# Example 5: React to status changes
# Escalated.hooks.add_action("ticket_status_changed") do |ticket, old_status, new_status, _actor|
#   Rails.logger.info "[HelloWorld] Ticket #{ticket.reference}: #{old_status} -> #{new_status}"
# end
