# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.6.2] - 2026-09-13

### Security
- **Webhook URLs could point at internal addresses, and signatures proved
  nothing.**
  - **URL checks:** admin webhooks and the workflow `send_webhook` action now
    refuse loopback, private and link-local destinations. The check runs when a
    webhook is saved and again at delivery, and delivery connects to the
    address that was checked and does not follow redirects. Set
    `allow_private_webhook_urls` to allow internal destinations.
  - **Signing:** requests to `webhook_url` were signed with a key published in
    the gem whenever `hosted_api_key` was unset. They are now signed with the
    new `webhook_secret` (or `hosted_api_key`), and unsigned when neither is set
    (#85).
- **The plugin store query built SQL from field names.** Field paths are now
  validated as plain dotted names before they reach the SQL (#87).

### Fixed
- **Every public endpoint ran the host's login filter.** Inbound mail, the
  widget, widget chat, guest tickets, newsletter tracking, unsubscribe and
  view-in-browser links, and plugin webhooks inherited the configured
  middleware, so callers were redirected to the host's sign-in page. They now
  inherit `Escalated::PublicController`, which skips it. `current_user` is read
  safely when the host defines none. `GET /support/widget/config` also no
  longer recurses until the stack runs out (the action was named `config`) (#84).
- **The admin webhooks screen was broken end to end.**
  - **Screens:** the index and delivery log answered 500, and create, update and
    retry called methods, columns and a service that don't exist. The
    controller now matches the models and the shared frontend's Index, Form and
    DeliveryLog pages.
  - **Deliveries:** `WebhookDispatcher` had no caller. Ticket and reply events
    are now delivered to subscribed webhooks, each in a
    `Escalated::DeliverWebhookJob`.
  - **Query strings:** URLs keep their query string, and a bare host no longer
    raises (#85).
- **Ticket hooks and several events never fired.**
  - **Plugin hooks:** the documented `ticket_*` and `reply_added` hooks now fire
    from the dispatch path, so Ruby plugins and the Node bridge receive them.
  - **Escalations:** every escalation dispatches `ticket_escalated`, not only
    those that send an email, and a rule's priority, status, assignee and
    department changes are dispatched once committed.
  - **SLA warnings:** `sla_warning` reaches the workflow subscriber, and
    `sla.warning` is a workflow trigger again.
  - **Broadcasts:** the status-change broadcast reports the real old status.
  - **Webhook URL:** hosts with `webhook_url` now also receive `ticket_updated`,
    `department_changed` and `sla_warning` (#86).
- **Plugin store queries and contact metadata segments failed on SQLite and
  PostgreSQL.** They used MySQL-only JSON functions, and PostgreSQL also
  rejected `LIKE` on the json column. On MySQL, numbers sorted as text and
  metadata rules matched nothing. A new adapter-aware `JsonQuery` helper
  compares numbers as numbers on all three databases, and segment rules honour
  their operator (#87).
- **Rake tasks ran twice.** The engine loaded its import and chat task files
  again after Rails had loaded them, so `escalated:import:run` imported, ran
  again and exited 1 (#83).
- **`mailer_from` could not be configured.** The mailers read it but
  `Configuration` had no such setting, so every email came from
  `support@example.com`. A display-name address is parsed correctly for the
  Message-ID domain (#82).

## [0.6.1] - 2026-09-13

### Fixed
- **The engine could not be installed on MySQL.** `rails db:migrate` stopped on the first of four incompatibilities, each surfacing as a raw adapter error rather than naming its cause: eight JSON columns carried a database default, which MySQL forbids; `import_jobs` used `id: :uuid`, a type MySQL does not have; `newsletter_list_members.added_at` defaulted to `CURRENT_TIMESTAMP`, which MySQL rejects on the `datetime(6)` column Rails creates; and the settings seed wrote iso8601 timestamps into raw SQL, whose `T` and `Z` MySQL refuses.

  The JSON defaults moved to the models, where every adapter honours them the same way. PostgreSQL keeps its native `uuid` column, which existing installs already have; elsewhere the id is a 36-character string that `Escalated::ImportJob` generates. `Escalated::NewsletterListMember` stamps `added_at` on create, and the seed asks the adapter for its own `quoted_date`.

- **Twenty-five screens rendered blank.** They rendered page names with no component behind them in `@escalated-dev/escalated`, and Inertia resolves such a name to nothing rather than to an error, so each returned 200 and an empty panel. Fifteen are renamed to the component the frontend ships, among them `Admin/Workflows/{Edit,New,Show}` to `Admin/Workflows/Form` and `Admin/Imports/Show` to `Admin/Import/Progress`. `Escalated/Error`, rendered for every 403 and 404 inside the panel, now exists in `@escalated-dev/escalated` 0.11.5.

  Five of those needed their props fixed too, or they would have resolved and still shown nothing. The escalation rule and SLA policy forms read `rule` and `policy`. Articles, audit logs and webhook deliveries now get the paginator shape their list components page through, where they showed the first page with no way past it. The overview report takes its figures flat, where it had rendered zeroes that read as a quiet week. Eight names stay blank because this engine's surface is a different shape from the component's: six advanced reports, `Settings/Csat` and `Settings/Sso`.

- **Turning on two-factor authentication from the admin settings never worked.** Setup rendered `Escalated/Admin/Settings/TwoFactorSetup`, which the frontend does not ship; it generated the secret with `ROTP::Base32.random`, though `rotp` is not a dependency; and confirming called `Escalated::TwoFactor.create_or_update_for`, which was never defined.

  The controller now drives the enrolment the shared `Admin/Settings/TwoFactor` page runs, following escalated-laravel. Setup stores a secret and eight recovery codes from the engine's own `TwoFactorService` and flashes the QR URI; confirm checks the posted code against the stored secret rather than one round-tripped through the form; and the index passes `enabled` and `pending`. The engine still does not ask for a second factor at sign-in, so this makes enrolment work without yet enforcing it.

- **The shared workflow builder could not save a workflow.** `workflow_params` read the body under a `workflow` key that exists only when the host turns on ParamsWrapper, so every create was a 400, and even a wrapped body lost its actions, because `actions: []` permits only arrays of scalars. The trigger list also disagreed with what fires: `ticket.replied` and `ticket.escalated` were refused, while seven events nothing dispatches were accepted and offered.

  The endpoints now follow escalated-developer-context `domain-model/workflow-admin-contract.md`. The body is read top-level, a workflow needs at least one action, omitted conditions are stored as `{ "all": [] }`, and `trigger_event` must be one of the seven events something dispatches, which is also the list the form offers. A failed save returns field errors through the session for `useForm`, and the create form gets `workflow: null`. The engine handles `insert_canned_reply`, and `{ "any": [] }` matches every ticket. `delay` and `send_notification` are no longer offered, since neither does anything with the builder's shape, but rows that store them still run.

### Changed
- **The test suite runs on PostgreSQL and MySQL as well as SQLite.** `spec/dummy/config/database.yml` reads `ESCALATED_TEST_ADAPTER` (`sqlite3`, `postgresql` or `mysql2`) and defaults to SQLite, so running the suite locally still needs nothing installed. An unrecognised value raises rather than falling back, because a CI leg that quietly ran SQLite would report green having tested nothing the matrix exists for.

### Added
- **`spec/page_name_parity_spec.rb`**, asserting every page name this engine renders resolves to a component. It diffs them against the manifest the frontend publishes, vendored at `spec/fixtures/escalated-pages.json`, and fails if its list of known-blank names still excuses one that has since been fixed, so that list can only shrink.

## [0.6.0] - 2026-09-12

### Added
- **Configurable database connection.** `Escalated.configuration.database_connection` names the database Escalated's own tables live on. `nil` keeps the host application's primary connection, which is the historical behaviour and leaves an unconfigured host unchanged.

  Accepts either shape Rails offers: a Symbol/String establishes that `database.yml` entry directly, and a Hash is passed to `connects_to` so a host already using role-based multiple databases keeps its reading/writing split.

  Every Escalated model inherits `Escalated::ApplicationRecord`, so one setting moves all of them together; a spec enumerates `app/models/escalated` and fails if a model is ever added that does not inherit it. The long-running import checkout now takes Escalated's pool rather than `ActiveRecord::Base`'s, which would otherwise hold the wrong connection open for the whole import.

  Your user table is deliberately not moved — it belongs to the host, and Escalated stores host user ids as plain unconstrained columns so the two can live on different connections with no foreign key to span them.

  Migrations follow Rails' own rule: install them into the migration path for that database (`MIGRATIONS_PATH=db/support_migrate`) and run `db:migrate:support`. See the README.

### Added
- Consume central translations from the `escalated-locale` gem; plugin-local `config/locales/*.yml` and a new `config/locales/overrides/` directory still override central keys (last-loaded wins)
- SAML and JWT validation in SSO service
- Full automation system matching Laravel AutomationRunner
- Ticket type validation, scope, and controller filtering
- Permission seed with default roles
- Plugin bridge for Rails backend
- Import framework ported from Laravel
- `show_powered_by` setting
- Platform parity with Laravel (phases 1-5)
- Multi-language (i18n) support with EN, ES, FR, DE translations
- WordPress-style plugin/extension system with gem discovery and source badges
- REST API layer with token auth, rate limiting, and full ticket CRUD
- RSpec test suite
- GitHub Actions CI build pipeline
- Plugin SDK section and plugin authoring guide
- Inertia UI optional with `ui_enabled` config

### Fixed
- Reject webhooks when auth credentials are missing

## [0.4.0] - 2026-02-09

### Added
- Bulk actions for assigning, changing status/priority, adding tags, closing, or deleting multiple tickets
- Macros for reusable multi-step automations
- Ticket followers with shared notifications
- Satisfaction ratings (1-5 star CSAT) with optional comments
- Pinned internal notes
- Keyboard shortcuts for power users
- Quick filter chips (My Tickets, Unassigned, Urgent, SLA Breaching)
- Presence indicators for real-time ticket viewing
- Enhanced dashboard with CSAT metrics, resolution times, and SLA breach tracking

## [0.1.9] - 2026-02-08

### Security
- Fix SSRF, XSS, auth bypass, sort injection, and credential exposure vulnerabilities

## [0.1.8] - 2026-02-08

### Added
- Inbound email system with Mailgun, Postmark, AWS SES, and IMAP adapters
- Admin settings for inbound email configuration

## [0.1.7] - 2026-02-08

### Added
- Initial release of Escalated Rails engine
- Admin ticket management and configurable reference prefix
- EscalatedSettings model and guest ticket support
- Frontend assets moved to `@escalated-dev/escalated` npm package
- EscalatedPlugin theming with layout integration
