# Running Escalated for Rails

## Hosting Modes

### Self-Hosted (default)

Everything stays in your database. No external calls. Full autonomy.

```ruby
Escalated.configure do |config|
  config.mode = :self_hosted
end
```

### Synced

Local database + automatic sync to `cloud.escalated.dev` for unified inbox across multiple apps. If the cloud is unreachable, your app keeps working — events queue and retry.

```ruby
Escalated.configure do |config|
  config.mode = :synced
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

Agent actions taken in the cloud portal come back through a signed webhook. Set the
site's signing secret (shown on the connected site in the cloud dashboard) and give
the cloud this URL:

```ruby
config.hosted_signing_secret = ENV["ESCALATED_CLOUD_SIGNING_SECRET"]
# Webhook URL for the connected site: https://your-app.example.com/support/cloud/webhook
```

The receiver verifies `X-Escalated-Signature` (HMAC-SHA256 of the raw body), ignores replayed
`event_id`s for 24 hours, and applies subject, description, priority and status from
`ticket.updated` / `ticket.status_changed` to the local ticket whose `reference` matches the
projection's `external_id`. Changes run through the local driver, so your listeners fire, and
are not echoed back to the cloud.

### Cloud

All ticket data proxied to the cloud API. Your app handles auth and renders UI, but storage lives in the cloud.

```ruby
Escalated.configure do |config|
  config.mode = :cloud
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

All three modes share the same controllers, UI, and business logic. The driver pattern handles the rest.

## Configuration

Create or edit `config/initializers/escalated.rb`:

```ruby
Escalated.configure do |config|
  config.mode = :self_hosted
  config.user_class = "User"
  config.table_prefix = "escalated_"
  config.route_prefix = "support"
  config.default_priority = :medium

  # Host user key type for the engine's user-referencing FK columns.
  # :auto (default) introspects your `user_class` primary key; override with
  # :bigint | :uuid | :string if your User model uses a UUID/string PK. Run
  # `escalated:install:migrations` AFTER setting this so the generated
  # migrations emit matching column types.
  config.user_id_type = :auto

  # Middleware
  config.middleware = [:authenticate_user!]
  config.admin_middleware = nil

  # Tickets
  config.allow_customer_close = true
  config.auto_close_resolved_after_days = 7
  config.max_attachments_per_reply = 5
  config.max_attachment_size_kb = 10240

  # SLA
  config.sla = {
    enabled: true,
    business_hours_only: true,
    business_hours: {
      start: 9, end: 17,
      timezone: "UTC",
      working_days: [1, 2, 3, 4, 5]
    }
  }

  # Notifications
  config.notification_channels = [:email]
  config.webhook_url = nil
  config.webhook_secret = nil              # signs requests to webhook_url (X-Escalated-Signature)
  config.allow_private_webhook_urls = false # let admin webhooks reach private addresses

  # Storage (ActiveStorage)
  config.storage_service = :local
end
```

## Scheduling

Add these to your scheduler for SLA and escalation automation:

```ruby
# config/schedule.rb (whenever gem) or use solid_queue/sidekiq-cron
every 1.minute do
  runner "Escalated::CheckSlaJob.perform_now"
end

every 5.minutes do
  runner "Escalated::EvaluateEscalationsJob.perform_now"
end

every 1.day do
  runner "Escalated::CloseResolvedJob.perform_now"
end

every 1.week do
  runner "Escalated::PurgeActivitiesJob.perform_now"
end

# SDK plugins' cron schedules (only with the plugin runtime)
every 1.minute do
  rake "escalated:plugins:cron"
end
```

`Escalated::PurgeExpiredDataJob` (also `rake escalated:purge_expired`, with `DRY_RUN=1` to only count) applies the retention periods set on the admin Data Retention screen. Every period defaults to `never`, so until one is set it only clears expired guest verification codes. Purged tickets are destroyed, not soft-deleted:

```ruby
every 1.day do
  runner "Escalated::PurgeExpiredDataJob.perform_now"
end
```

## Routes

Routes are automatically mounted when the engine loads. By default they mount at `/support`.

| Route | Method | Description |
|-------|--------|-------------|
| `/support` | GET | Customer ticket list |
| `/support/create` | GET | New ticket form |
| `/support/{ticket}` | GET | Ticket detail |
| `/support/agent` | GET | Agent dashboard |
| `/support/agent/tickets` | GET | Agent ticket queue |
| `/support/agent/tickets/{ticket}` | GET | Agent ticket view |
| `/support/admin/reports` | GET | Admin reports |
| `/support/admin/departments` | GET | Department management |
| `/support/admin/sla-policies` | GET | SLA policy management |
| `/support/admin/escalation-rules` | GET | Escalation rule management |
| `/support/admin/tags` | GET | Tag management |
| `/support/admin/canned-responses` | GET | Canned response management |
| `/support/agent/tickets/bulk` | POST | Bulk actions on multiple tickets |
| `/support/agent/tickets/{ticket}/follow` | POST | Follow/unfollow a ticket |
| `/support/agent/tickets/{ticket}/macro` | POST | Apply a macro to a ticket |
| `/support/agent/tickets/{ticket}/presence` | POST | Update presence on a ticket |
| `/support/agent/tickets/{ticket}/pin/{reply}` | POST | Pin/unpin an internal note |
| `/support/{ticket}/rate` | POST | Submit satisfaction rating |

## Events

Connect to ticket lifecycle events via ActiveSupport::Notifications:

```ruby
ActiveSupport::Notifications.subscribe("escalated.ticket_created") do |event|
  ticket = event.payload[:ticket]
  # Handle new ticket
end
```

## Custom Ticket Actions

Host applications can add custom buttons to the agent ticket screen and handle
clicks with a normal notification subscriber. Register actions in the initializer:

```ruby
Escalated.configure do |config|
  config.ticket_actions = [
    {
      key: 'sync-crm',
      label: 'Sync CRM',
      variant: 'primary',                       # primary | secondary | danger
      confirmation: 'Sync this ticket to the CRM?',
      metadata: { icon: 'refresh-cw' },
      # visible / enabled may be a value or a ->(ticket, user) callable
      enabled: ->(ticket, _user) { !ticket.metadata['crm_synced'] }
    }
  ]
end
```

Visible actions are exposed on the agent ticket show page as `customActions` and
on the API ticket detail response as `custom_actions` (each with a `url` and
`method`). Triggering one (`POST /support/agent/tickets/:id/actions/:action_key`
or the API equivalent) validates the action is visible (404) and enabled (403),
then dispatches the `custom_action_triggered` notification:

```ruby
ActiveSupport::Notifications.subscribe('escalated.notification.custom_action_triggered') do |event|
  payload = event.payload
  next unless payload[:action_key] == 'sync-crm'
  # payload[:ticket], payload[:user], payload[:payload], payload[:metadata]
end
```

Escalated also records an internal note on the ticket whenever an action fires,
for auditability.

## Testing

```bash
bundle exec rspec
```

## Database connection

By default Escalated's tables live on your application's primary database. Name
a different one to keep them somewhere else — a schema shared with a legacy
system, a multi-tenant split, a separate reporting store, or simply out of your
primary database:

```ruby
# config/initializers/escalated.rb
Escalated.configure do |config|
  config.database_connection = :support
end
```

`:support` is an entry in your `config/database.yml`. Hosts already using
Rails' role-based multiple databases can pass the mapping instead, and the
reading/writing split is preserved:

```ruby
config.database_connection = { writing: :support_primary, reading: :support_replica }
```

Every Escalated model inherits `Escalated::ApplicationRecord`, so one setting
moves all of them together. A spec enumerates `app/models/escalated` and fails
if a model is ever added that does not inherit it.

**Your user table does not move.** It belongs to your application, and
Escalated stores host user ids as plain unconstrained columns precisely so the
two can live on different connections — there is no foreign key that would have
to span them.

### Migrations

Rails decides which database a migration runs against by which migration path
it lives in, so install Escalated's into the path for that database rather than
the primary one:

```ruby
# config/database.yml
support:
  adapter: postgresql
  database: support
  migrations_paths: db/support_migrate
```

```bash
bin/rails escalated:install:migrations MIGRATIONS_PATH=db/support_migrate
bin/rails db:migrate:support
```

Setting `database_connection` on an existing install does not move existing
data. Migrate the tables and copy the rows across before pointing Escalated at
the new database.
