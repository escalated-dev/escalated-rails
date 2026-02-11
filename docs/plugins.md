# Building Plugins

Plugins extend Escalated with custom functionality using a WordPress-style hook system. Plugins can be distributed as ZIP files (uploaded via the admin panel) or as Ruby gems.

## Plugin Structure

A minimal plugin needs two files:

```
my-plugin/
  plugin.json      # Manifest (required)
  plugin.rb        # Entry point (required)
```

### plugin.json

```json
{
    "name": "My Plugin",
    "slug": "my-plugin",
    "description": "A short description of what this plugin does.",
    "version": "1.0.0",
    "author": "Your Name",
    "author_url": "https://example.com",
    "requires": "1.0.0",
    "main_file": "plugin.rb"
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Human-readable plugin name |
| `slug` | Yes | Unique identifier (lowercase, hyphens only) |
| `description` | No | Short description shown in the admin panel |
| `version` | Yes | Semver version string |
| `author` | No | Author name |
| `author_url` | No | Author website URL |
| `requires` | No | Minimum Escalated version required |
| `main_file` | No | Entry point filename (defaults to `plugin.rb`) |

### plugin.rb

The main file is loaded via `require` when the plugin is activated. Use it to register hooks:

```ruby
# Runs every time a ticket is created
Escalated.hooks.add_action("ticket_created") do |ticket|
  # Send a Slack notification, create a Jira issue, etc.
  Rails.logger.info("New ticket: #{ticket.reference}")
end

# Modify ticket data before it's saved
Escalated.hooks.add_filter("ticket_data") do |data|
  data[:custom_field] = "value"
  data
end
```

## Distribution Methods

### ZIP Upload (Local Plugins)

1. Create a ZIP file containing your plugin folder at the root:
   ```
   my-plugin.zip
     └── my-plugin/
           ├── plugin.json
           └── plugin.rb
   ```
2. Go to **Admin > Plugins** and upload the ZIP file.
3. Click **Inactive** to activate the plugin.

Uploaded plugins are stored in `lib/escalated/plugins/`.

### Gem Package

Any gem that includes a `plugin.json` at its root is automatically detected:

```
gem install escalated-billing
```

Or add to your Gemfile:

```ruby
gem "escalated-billing"
```

The gem just needs a `plugin.json` alongside its gemspec:

```
gems/escalated-billing/
  escalated-billing.gemspec
  plugin.json        # ← Escalated detects this
  lib/
    escalated/
      billing/
        plugin.rb
    ...
```

Gem plugins appear in the admin panel with a **composer** badge. They cannot be deleted from the UI — use `bundle remove` instead.

**Gem plugin slugs** are derived from the gem name: `escalated-billing` stays `escalated-billing`.

## Hook API

### Action Hooks

Actions let you run code when something happens. They don't return a value.

```ruby
# Register an action
Escalated.hooks.add_action(tag, priority: 10) { |*args| ... }

# Fire an action (used internally by Escalated)
Escalated.hooks.do_action(tag, *args)

# Check if an action has callbacks
Escalated.hooks.has_action?(tag)

# Remove an action
Escalated.hooks.remove_action(tag, callback = nil)
```

### Filter Hooks

Filters let you modify data as it passes through the system. Callbacks receive the current value and must return the modified value.

```ruby
# Register a filter
Escalated.hooks.add_filter(tag, priority: 10) { |value, *args| value }

# Apply filters (used internally by Escalated)
Escalated.hooks.apply_filters(tag, value, *args)

# Check if a filter has callbacks
Escalated.hooks.has_filter?(tag)

# Remove a filter
Escalated.hooks.remove_filter(tag, callback = nil)
```

### Priority

Lower numbers run first. The default priority is `10`. Use lower values (e.g. `5`) to run before other callbacks, or higher values (e.g. `20`) to run after.

```ruby
# This runs first
Escalated.hooks.add_action("ticket_created", priority: 5) do |ticket|
  # early processing
end

# This runs second
Escalated.hooks.add_action("ticket_created", priority: 20) do |ticket|
  # later processing
end
```

## Available Hooks

### Plugin Lifecycle

| Hook | Args | When |
|------|------|------|
| `plugin_loaded` | `slug, manifest` | Plugin file is loaded |
| `plugin_activated` | `slug` | Plugin is activated |
| `plugin_activated_{slug}` | — | Your specific plugin is activated |
| `plugin_deactivated` | `slug` | Plugin is deactivated |
| `plugin_deactivated_{slug}` | — | Your specific plugin is deactivated |
| `plugin_uninstalling` | `slug` | Plugin is about to be deleted |
| `plugin_uninstalling_{slug}` | — | Your specific plugin is about to be deleted |

Use the `{slug}` variants to run code only for your own plugin:

```ruby
Escalated.hooks.add_action("plugin_activated_my-plugin") do
  # Run migrations, seed data, etc.
end

Escalated.hooks.add_action("plugin_uninstalling_my-plugin") do
  # Clean up database tables, cached files, etc.
end
```

## UI Helpers

Plugins can register UI elements that appear in the Escalated interface.

### Menu Items

```ruby
Escalated.plugin_ui.add_menu_item({
  label: "Billing",
  url: "/support/admin/billing",
  icon: "M2.25 8.25h19.5M2.25 9h19.5m-16.5...",  # Heroicon SVG path
  section: "admin",  # 'admin', 'agent', or 'customer'
  priority: 50
})
```

### Custom Pages

```ruby
Escalated.plugin_ui.register_page(
  "admin/billing",                    # Route path
  "Escalated/Admin/Billing",          # Inertia component
  { middleware: ["auth"] }            # Options
)
```

### Dashboard Widgets

```ruby
Escalated.plugin_ui.add_dashboard_widget({
  id: "billing-summary",
  label: "Billing Summary",
  component: "BillingSummaryWidget",
  section: "agent",
  priority: 10
})
```

### Page Components (Slots)

Inject components into existing pages:

```ruby
Escalated.plugin_ui.add_page_component(
  "ticket-detail",   # Page identifier
  "sidebar",         # Slot name
  {
    component: "BillingInfo",
    props: { show_total: true },
    priority: 10
  }
)
```

## Full Example: Slack Notifier Plugin

```
slack-notifier/
  plugin.json
  plugin.rb
```

**plugin.json:**
```json
{
    "name": "Slack Notifier",
    "slug": "slack-notifier",
    "description": "Posts a message to Slack when a new ticket is created.",
    "version": "1.0.0",
    "author": "Acme Corp",
    "main_file": "plugin.rb"
}
```

**plugin.rb:**
```ruby
require "net/http"
require "json"

Escalated.hooks.add_action("plugin_activated_slack-notifier") do
  Rails.logger.info("Slack Notifier plugin activated")
end

Escalated.hooks.add_action("ticket_created") do |ticket|
  webhook_url = Rails.application.credentials.dig(:slack, :webhook_url)
  next unless webhook_url

  uri = URI(webhook_url)
  Net::HTTP.post(uri, { text: "New ticket *#{ticket.reference}*: #{ticket.subject}" }.to_json, "Content-Type" => "application/json")
end

Escalated.hooks.add_action("plugin_uninstalling_slack-notifier") do
  Rails.logger.info("Slack Notifier plugin uninstalled")
end
```

## Full Example: Gem Package

A gem-distributed plugin follows the same conventions. Your gemspec and `plugin.json` live side by side:

**escalated-billing.gemspec:**
```ruby
Gem::Specification.new do |spec|
  spec.name        = "escalated-billing"
  spec.version     = "2.0.0"
  spec.authors     = ["Acme Corp"]
  spec.email       = ["dev@acme.com"]
  spec.summary     = "Billing integration for Escalated"
  spec.description = "Adds billing and invoicing to Escalated."
  spec.homepage    = "https://github.com/acme/escalated-billing"
  spec.license     = "MIT"

  spec.files = Dir["{lib}/**/*", "plugin.json", "plugin.rb", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 7.0"
end
```

**plugin.json:**
```json
{
    "name": "Billing Integration",
    "slug": "escalated-billing",
    "description": "Adds billing and invoicing to Escalated.",
    "version": "2.0.0",
    "author": "Acme Corp",
    "main_file": "plugin.rb"
}
```

**plugin.rb:**
```ruby
require "escalated/billing"

Escalated.hooks.add_action("ticket_created") do |ticket|
  Escalated::Billing::Service.new.track_ticket(ticket)
end

Escalated.plugin_ui.add_menu_item({
  label: "Billing",
  url: "/support/admin/billing",
  icon: "M2.25 18.75a60.07 60.07 0 0115.797 2.101c.727.198 1.453-.342 1.453-1.096V18.75M3.75 4.5v.75A.75.75 0 013 6h-.75m0 0v-.375c0-.621.504-1.125 1.125-1.125H20.25M2.25 6v9m18-10.5v.75c0 .414.336.75.75.75h.75m-1.5-1.5h.375c.621 0 1.125.504 1.125 1.125v9.75c0 .621-.504 1.125-1.125 1.125h-.375m1.5-1.5H21a.75.75 0 00-.75.75v.75m0 0H3.75m0 0h-.375a1.125 1.125 0 01-1.125-1.125V15m1.5 1.5v-.75A.75.75 0 003 15h-.75M15 10.5a3 3 0 11-6 0 3 3 0 016 0zm3 0h.008v.008H18V10.5zm-12 0h.008v.008H6V10.5z",
  section: "admin",
  priority: 50
})
```

Since the gem handles autoloading, your `plugin.rb` can use classes from `lib/` without any manual `require` statements.

## Tips

- **Keep plugin.rb lightweight.** Register hooks and delegate to service classes.
- **Use activation hooks** to run migrations or seed data on first activation.
- **Use uninstall hooks** to clean up database tables when your plugin is removed.
- **Namespace your hooks** to avoid collisions: `myplugin_custom_action`.
- **Test locally** by placing your plugin folder in `lib/escalated/plugins/` and activating it from the admin panel.
- **Gem plugins** benefit from Bundler's dependency management, testing infrastructure, and version management via RubyGems.
