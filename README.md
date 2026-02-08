# Escalated

A full-featured, embeddable support ticket system for Rails applications. Supports SLA management, escalation rules, department routing, and three hosting modes.

Uses **Inertia.js + Vue 3** for the frontend (not Hotwire).

## Installation

Add to your Gemfile:

```ruby
gem "escalated"
```

Run the installer:

```bash
bundle install
rails generate escalated:install
rails db:migrate
```

## Configuration

Create or edit `config/initializers/escalated.rb`:

```ruby
Escalated.configure do |config|
  # Hosting mode: :self_hosted, :synced, or :cloud
  config.mode = :self_hosted

  # Your user model class name
  config.user_class = "User"

  # Table prefix for all Escalated tables
  config.table_prefix = "escalated_"

  # Route prefix (mounts at /support by default)
  config.route_prefix = "support"

  # Middleware applied to all Escalated routes
  config.middleware = [:authenticate_user!]

  # Additional middleware for admin routes
  config.admin_middleware = nil

  # SLA configuration
  config.sla = {
    enabled: true,
    business_hours_only: true,
    business_hours: {
      start: 9,
      end: 17,
      timezone: "UTC",
      working_days: [1, 2, 3, 4, 5]
    }
  }

  # Notification channels
  config.notification_channels = [:email]

  # Webhook URL for external integrations
  config.webhook_url = nil
end
```

## Hosting Modes

### Self-Hosted (default)
All data stored in your local database. Full control.

### Synced
Data stored locally AND synced to Escalated Cloud. Local-first with cloud backup.

### Cloud
All operations proxied to Escalated Cloud API. No local database tables needed.

```ruby
Escalated.configure do |config|
  config.mode = :cloud
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

## Frontend Setup

Escalated uses Inertia.js with Vue 3. Add the Escalated Vue pages to your Inertia resolver:

```javascript
// app/javascript/pages/index.js
const pages = import.meta.glob('../pages/**/*.vue', { eager: true })
const escalatedPages = import.meta.glob('../../vendor/escalated/**/*.vue', { eager: true })

// Merge into your Inertia resolver
```

## Mounting Routes

Routes are automatically mounted when the engine loads. By default they mount at `/support`.

## License

MIT License. See LICENSE file.
