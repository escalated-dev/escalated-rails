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

The webhook route is drawn only while `hosted_signing_secret` is set. Without a secret
there is nothing to verify a request against, so `POST /support/cloud/webhook` does not exist.

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
  # Extra guards on the customer portal and customer knowledge base only, run
  # after `middleware`: before_action method names or callables taking the
  # controller. Default []. See "Staff-only installs" below.
  config.customer_middleware = []

  # Optional public routes. Each defaults to on; off means its routes are not drawn.
  config.widget_enabled = true        # ESCALATED_WIDGET_ENABLED: every {route_prefix}/widget route
  config.guest_routes_enabled = true  # ESCALATED_GUEST_ROUTES: every {route_prefix}/guest route

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

## Required: schedule the recurring jobs

Rails has no in-process scheduler an engine can register with, so **SLA checks, escalation rules,
automations and snooze wake-ups do not run until your app schedules them**. Nothing fails loudly
when they are missing: SLAs simply never breach and snoozed tickets never wake.

| Job | Interval | What it does |
|-----|----------|--------------|
| `Escalated::CheckSlaJob` | every minute | SLA breaches and warnings; also records the scheduler heartbeat |
| `Escalated::EvaluateEscalationsJob` | every 5 minutes | Escalation rules |
| `Escalated::RunAutomationsJob` | every 5 minutes | Time-based automations (`rake escalated:run_automations`) |
| `Escalated::WakeSnoozedTicketsJob` | every minute | Wakes snoozed tickets (`rake escalated:wake_snoozed_tickets`) |
| `Escalated::CloseResolvedJob` | daily | Closes tickets resolved more than `auto_close_resolved_after_days` ago |
| `Escalated::PurgeActivitiesJob` | weekly | Trims old ticket activity |

With Solid Queue (the Rails 8 default), add them to `config/recurring.yml`:

```yaml
production:
  escalated_check_sla:
    class: Escalated::CheckSlaJob
    schedule: every minute
  escalated_evaluate_escalations:
    class: Escalated::EvaluateEscalationsJob
    schedule: every 5 minutes
  escalated_run_automations:
    class: Escalated::RunAutomationsJob
    schedule: every 5 minutes
  escalated_wake_snoozed_tickets:
    class: Escalated::WakeSnoozedTicketsJob
    schedule: every minute
  escalated_close_resolved:
    class: Escalated::CloseResolvedJob
    schedule: every day at 3am
  escalated_purge_activities:
    class: Escalated::PurgeActivitiesJob
    schedule: every sunday at 4am
```

The jobs run on the `escalated` queue, so make sure a worker processes it. With sidekiq-cron, list
the same classes and cron expressions. With the `whenever` gem or plain cron:

```ruby
# config/schedule.rb
every 1.minute do
  runner "Escalated::CheckSlaJob.perform_now"
  runner "Escalated::WakeSnoozedTicketsJob.perform_now"
end

every 5.minutes do
  runner "Escalated::EvaluateEscalationsJob.perform_now"
  runner "Escalated::RunAutomationsJob.perform_now"
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

**How to tell they run.** Each run of `Escalated::CheckSlaJob` records a heartbeat (the
`scheduler_heartbeat_at` row in the settings table). When it is missing or more than 15 minutes
old, the admin Settings, Reports and Reports dashboard pages get a `scheduler` prop with
`healthy: false`, the message and the list above, and a warning is logged. Headless installs get
the same object under `scheduler` in `GET {api_prefix}/dashboard` for admin tokens.
`bin/rails escalated:doctor` prints it too.

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

### Optional public routes

Some routes take no sign-in. Each is drawn only while its feature is on, so an install that does
not use one carries none of its routes:

| Routes | Drawn while | Default |
|--------|-------------|---------|
| `/support/widget/...` (widget, widget chat, `embed.js`) | `config.widget_enabled` / `ESCALATED_WIDGET_ENABLED` | on |
| `/support/guest/...` (guest portal) | `config.guest_routes_enabled` / `ESCALATED_GUEST_ROUTES` | on |
| `/support/cloud/webhook` | `config.hosted_signing_secret` is set | off until a secret is set |

`ESCALATED_WIDGET_ENABLED` and `ESCALATED_GUEST_ROUTES` accept `false`, `0`, `no` or `off`. The
guest portal's admin setting (Settings > Guest tickets) still turns the guest routes off at runtime
while `guest_routes_enabled` is on; with it off, the routes do not exist at all and the portal
stops linking to them. Routes are drawn at boot, so restart after changing these.

### Staff-only installs

By default any signed-in user can use the customer portal and the customer knowledge base: list
their tickets, raise new ones and read articles. When only your staff use Escalated, add a guard
to those routes with `config.customer_middleware`, and switch off the public routes you do not use:

```ruby
Escalated.configure do |config|
  # Run after config.middleware on /support/customer/* (tickets, ratings and
  # the knowledge base) and the /support root. Method names of
  # Escalated::ApplicationController or your own guards, or callables taking
  # the controller; the first that renders or redirects stops the request.
  config.customer_middleware = [:require_staff!]
  # e.g. a 403 instead of the redirect:
  # config.customer_middleware = [->(c) { c.head :forbidden unless c.send(:current_user)&.escalated_agent? }]

  config.guest_routes_enabled = false
  config.widget_enabled = false
end
```

`:require_staff!` lets agents and admins (`escalated_agent?` / `escalated_admin?`) through and
redirects anyone else to your root with the "not an agent" message. A guard name the controller
does not have raises an error rather than being skipped.

## Checking the setup

`bin/rails escalated:doctor` checks that `config.user_class` loads and defines
`escalated_agent?`, `escalated_admin?` and `.escalated_agents`, and whether the recurring jobs
run (the heartbeat above). It exits non-zero when the user model cannot say who is staff.
`rails generate escalated:install` runs it at the end.

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
