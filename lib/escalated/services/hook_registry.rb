module Escalated
  module Services
    # Central registry of all available hooks and filters in Escalated.
    # This class serves as documentation -- plugins can reference this to
    # discover what extension points are available.
    class HookRegistry
      class << self
        # Get all available action hooks.
        #
        # @return [Hash{String => Hash}]
        def actions
          {
            # ==============================================================
            # PLUGIN LIFECYCLE
            # ==============================================================
            "plugin_loaded" => {
              description: "Fired when a plugin file is loaded",
              parameters: %w[slug manifest],
              example: <<~RUBY
                Escalated.hooks.add_action('plugin_loaded') do |slug, manifest|
                  Rails.logger.info "Plugin loaded: \#{slug}"
                end
              RUBY
            },
            "plugin_activated" => {
              description: "Fired when any plugin is activated",
              parameters: %w[slug],
              example: <<~RUBY
                Escalated.hooks.add_action('plugin_activated') do |slug|
                  Rails.logger.info "Plugin activated: \#{slug}"
                end
              RUBY
            },
            "plugin_activated_{slug}" => {
              description: "Fired when a specific plugin is activated (replace {slug} with your plugin slug)",
              parameters: [],
              example: <<~RUBY
                Escalated.hooks.add_action('plugin_activated_my-plugin') { puts 'My plugin activated!' }
              RUBY
            },
            "plugin_deactivated" => {
              description: "Fired when any plugin is deactivated",
              parameters: %w[slug],
              example: <<~RUBY
                Escalated.hooks.add_action('plugin_deactivated') do |slug|
                  Rails.logger.info "Plugin deactivated: \#{slug}"
                end
              RUBY
            },
            "plugin_deactivated_{slug}" => {
              description: "Fired when a specific plugin is deactivated",
              parameters: [],
              example: <<~RUBY
                Escalated.hooks.add_action('plugin_deactivated_my-plugin') { puts 'Bye!' }
              RUBY
            },
            "plugin_uninstalling" => {
              description: "Fired before any plugin is deleted",
              parameters: %w[slug],
              example: <<~RUBY
                Escalated.hooks.add_action('plugin_uninstalling') do |slug|
                  Rails.logger.info "Plugin uninstalling: \#{slug}"
                end
              RUBY
            },
            "plugin_uninstalling_{slug}" => {
              description: "Fired before a specific plugin is deleted",
              parameters: [],
              example: <<~RUBY
                Escalated.hooks.add_action('plugin_uninstalling_my-plugin') { cleanup! }
              RUBY
            },

            # ==============================================================
            # TICKET LIFECYCLE
            # ==============================================================
            "ticket_before_create" => {
              description: "Fired before a ticket is created",
              parameters: %w[params],
              example: <<~RUBY
                Escalated.hooks.add_action('ticket_before_create') do |params|
                  # Modify or inspect params before creation
                end
              RUBY
            },
            "ticket_created" => {
              description: "Fired after a ticket is created",
              parameters: %w[ticket],
              example: <<~RUBY
                Escalated.hooks.add_action('ticket_created') do |ticket|
                  Rails.logger.info "Ticket created: \#{ticket.reference}"
                end
              RUBY
            },
            "ticket_updated" => {
              description: "Fired after a ticket is updated",
              parameters: %w[ticket actor],
              example: <<~RUBY
                Escalated.hooks.add_action('ticket_updated') do |ticket, actor|
                  Rails.logger.info "Ticket \#{ticket.reference} updated by \#{actor&.email}"
                end
              RUBY
            },
            "ticket_status_changed" => {
              description: "Fired when a ticket status changes",
              parameters: %w[ticket old_status new_status actor],
              example: <<~RUBY
                Escalated.hooks.add_action('ticket_status_changed') do |ticket, old_status, new_status, actor|
                  # React to status transitions
                end
              RUBY
            },
            "ticket_assigned" => {
              description: "Fired when a ticket is assigned to an agent",
              parameters: %w[ticket agent],
              example: <<~RUBY
                Escalated.hooks.add_action('ticket_assigned') do |ticket, agent|
                  Rails.logger.info "Ticket \#{ticket.reference} assigned to \#{agent.email}"
                end
              RUBY
            },
            "ticket_closed" => {
              description: "Fired when a ticket is closed",
              parameters: %w[ticket actor],
              example: <<~RUBY
                Escalated.hooks.add_action('ticket_closed') do |ticket, actor|
                  # Clean up or notify
                end
              RUBY
            },
            "ticket_reopened" => {
              description: "Fired when a ticket is reopened",
              parameters: %w[ticket actor],
              example: <<~RUBY
                Escalated.hooks.add_action('ticket_reopened') do |ticket, actor|
                  # Reassign or alert
                end
              RUBY
            },
            "reply_added" => {
              description: "Fired after a reply is added to a ticket",
              parameters: %w[ticket reply],
              example: <<~RUBY
                Escalated.hooks.add_action('reply_added') do |ticket, reply|
                  Rails.logger.info "Reply on \#{ticket.reference}"
                end
              RUBY
            },
            "ticket_priority_changed" => {
              description: "Fired when ticket priority changes",
              parameters: %w[ticket old_priority new_priority actor],
              example: <<~RUBY
                Escalated.hooks.add_action('ticket_priority_changed') do |ticket, old_p, new_p, actor|
                  # Alert if escalated to critical
                end
              RUBY
            },
            "ticket_department_changed" => {
              description: "Fired when a ticket is moved to another department",
              parameters: %w[ticket old_department new_department actor],
              example: <<~RUBY
                Escalated.hooks.add_action('ticket_department_changed') do |ticket, old_dept, new_dept, actor|
                  # Auto-assign in new department
                end
              RUBY
            },

            # ==============================================================
            # DASHBOARD / UI
            # ==============================================================
            "dashboard_viewed" => {
              description: "Fired when the agent dashboard is viewed",
              parameters: %w[user],
              example: <<~RUBY
                Escalated.hooks.add_action('dashboard_viewed') do |user|
                  # Track analytics
                end
              RUBY
            },
          }
        end

        # Get all available filter hooks.
        #
        # @return [Hash{String => Hash}]
        def filters
          {
            # ==============================================================
            # TICKET FILTERS
            # ==============================================================
            "ticket_create_params" => {
              description: "Modify validated params before creating a ticket",
              parameters: %w[params],
              example: <<~RUBY
                Escalated.hooks.add_filter('ticket_create_params') do |params|
                  params.merge(custom_field: 'value')
                end
              RUBY
            },
            "ticket_list_query" => {
              description: "Modify the ticket listing query",
              parameters: %w[query request],
              example: <<~RUBY
                Escalated.hooks.add_filter('ticket_list_query') do |query, request|
                  query.where(priority: :high)
                end
              RUBY
            },
            "ticket_show_data" => {
              description: "Modify ticket data before rendering the show page",
              parameters: %w[data ticket],
              example: <<~RUBY
                Escalated.hooks.add_filter('ticket_show_data') do |data, ticket|
                  data.merge(custom_widget: true)
                end
              RUBY
            },

            # ==============================================================
            # DASHBOARD FILTERS
            # ==============================================================
            "dashboard_stats_data" => {
              description: "Modify dashboard statistics before rendering",
              parameters: %w[stats user],
              example: <<~RUBY
                Escalated.hooks.add_filter('dashboard_stats_data') do |stats, user|
                  stats.merge(custom_metric: 42)
                end
              RUBY
            },
            "dashboard_page_data" => {
              description: "Modify all data passed to the dashboard page",
              parameters: %w[data user],
              example: <<~RUBY
                Escalated.hooks.add_filter('dashboard_page_data') do |data, user|
                  data.merge(announcements: fetch_announcements)
                end
              RUBY
            },

            # ==============================================================
            # UI FILTERS
            # ==============================================================
            "navigation_menu" => {
              description: "Add or modify navigation menu items",
              parameters: %w[menu_items user],
              example: <<~RUBY
                Escalated.hooks.add_filter('navigation_menu') do |items, user|
                  items + [{ label: 'Reports', route: '/reports' }]
                end
              RUBY
            },
            "sidebar_menu" => {
              description: "Add or modify sidebar menu items",
              parameters: %w[menu_items user],
              example: <<~RUBY
                Escalated.hooks.add_filter('sidebar_menu') do |items, user|
                  items + [{ label: 'Custom', icon: 'star' }]
                end
              RUBY
            },

            # ==============================================================
            # SLA FILTERS
            # ==============================================================
            "sla_response_deadline" => {
              description: "Modify the calculated SLA response deadline",
              parameters: %w[deadline ticket sla_policy],
              example: <<~RUBY
                Escalated.hooks.add_filter('sla_response_deadline') do |deadline, ticket, policy|
                  ticket.priority.to_s == 'critical' ? deadline - 1.hour : deadline
                end
              RUBY
            },

            # ==============================================================
            # NOTIFICATION FILTERS
            # ==============================================================
            "notification_recipients" => {
              description: "Modify notification recipients before dispatch",
              parameters: %w[recipients ticket event],
              example: <<~RUBY
                Escalated.hooks.add_filter('notification_recipients') do |recipients, ticket, event|
                  recipients + [admin_email]
                end
              RUBY
            },
          }
        end

        # Get all hooks (both actions and filters).
        #
        # @return [Hash{Symbol => Hash}]
        def all_hooks
          { actions: actions, filters: filters }
        end
      end
    end
  end
end
