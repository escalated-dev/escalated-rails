# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.7.10] - 2026-10-30

### Upgrading
- Hosts no longer need a hand-written `window.route` shim. Add `<%= escalated_route_helper_tag %>` to the Inertia layout ahead of the app's script and drop the shim, or keep the shim: a `window.route` the host installs still wins, so nothing changes until it is removed. Names the engine has no working endpoint for (agent snooze/unsnooze, ticket links, merge, side conversations, the all-workflows log) are not in the list; `login` is the host's and comes from `config.route_overrides`.

### Added
- **Built-in named route list for the shared frontend's `route()`** (`Escalated::RouteList`). Every Escalated Inertia response (staff, customer and guest screens) now carries a `ziggy` prop, `{ url, port: null, defaults: {}, routes: { name => { uri, methods } }, location }`, mapping the route names `@escalated-dev/escalated` calls to this engine's real paths under `route_prefix`. The `escalated_route_helper_tag` view helper installs a matching `route()` (only when `window.route` is not already a function; `window.Ziggy` is read first; an unknown name warns and returns `#`). `config.route_overrides` replaces or adds single names, for example `{ 'login' => '/users/sign_in' }`. See `docs/named-routes.md`.
- `POST {prefix}/admin/tickets/:id/split` with `reply_id` in the body, the path the split dialog posts to. `.../replies/:reply_id/split` still works.

## [0.7.9] - 2026-10-30

### Upgrading
- **Plugin `ctx.tickets.create`, `ctx.tickets.update` and `ctx.replies.create` now go through `TicketService`** (plugin contract, The plugin context), so a plugin's ticket or reply behaves like one written over the API. Before, they wrote the models directly and nothing else happened. Now a new ticket gets the default priority, a reference, the `ticket_created` activity and the default SLA, and is announced (`ticket.created` to workflows, webhooks, plugins and followers, the new-ticket mail and broadcast); a `status` on create or update is a status change (`status_changed` activity, `ticket.status_changed`, status mails); priority, department, subject and description changes are logged and announced (`ticket.priority_changed`, `ticket.department_changed`, `ticket.updated`); a reply or note is logged, sets the first response time and the agent/customer status flip like an API reply, and is announced (`reply.created` / `note.created`, reply mail). The author and causer is the signed-in user of the request the plugin is serving, or nobody. While a plugin action is being delivered, the same action raised by a plugin's own write (or `ctx.emit`) is not delivered to plugins again, and nesting stops at three, so a `ticket.created` handler that opens a ticket no longer triggers itself; webhooks and workflows still see every event.

## [0.7.8] - 2026-10-30

### Upgrading
- **`ctx.replies.create`, `ctx.tickets.create`, `ctx.tickets.update`, `ctx.contacts.create` and `ctx.tags.create` only accept the plugin contract's fields** (plugin contract, The plugin context). They passed the plugin's data straight to `create!`/`update!`, so a plugin could set a reply's author or internal/system flags, a ticket's requester, assignee or SLA fields, a tag's id, or any column of the host's user model (an admin flag included). Any other key is now an `ArgumentError` naming it. Replies: `ticket_id` (an existing ticket), `body`, `is_internal` (true makes a note); the author is the acting user, or nobody. Tickets: `subject`/`title`, `body`/`description` (the subject when blank, as a description is required), `priority`, `status`, `department_id`, `ticket_type`, `metadata`, and on create `channel` (accepted; tickets here have no channel column) and `contact_id` or `requester_email`/`requester_name` (a contact, found or created, also set as the guest name and email); never a requester id, assignee, reference or SLA field. Unknown priorities, statuses, ticket types, departments and contacts are errors. Contacts: `name`, `email`. Tags: `name`, `slug`, `color`. Plugins that sent other keys must drop them.

## [0.7.7] - 2026-10-30

### Upgrading
- **SDK plugin endpoints and webhooks moved to the plugin contract's paths, keyed by slug** (plugin contract, Endpoints and webhooks). Endpoints were `{prefix}/plugins/{name}/api/...` and webhooks `{prefix}/plugins/{name}/webhooks/...` (the name with everything outside `[a-z0-9_-]` dropped); they are now `{prefix}/api/plugins/{slug}{path}` and `{prefix}/webhooks/plugins/{slug}{path}`, where `@acme/plugin-crm` is `acme--plugin-crm`. The old URLs are 404: update any webhook URL registered with a third party. Endpoints now need the admin guard (they took any agent) plus an endpoint's declared `capability` (403), receive route `params` (from `:param` segments), `query` and `headers` without `Cookie`, `Authorization`, CSRF or `Proxy-*` headers, and a throwing endpoint answers 500 without its message. The engine no longer redraws its routes at boot (that cleared every route drawn before it); one route each serves every plugin, so activating a plugin needs no restart. Two plugins whose names give one slug are a configuration error: neither is served, and the log names both.
- **Single sign-on is an install-level switch, off by default** (`config.access = { sso: true }`, env `ESCALATED_SSO`; ADR 2026-10-29-configurable-access-features). Nothing ever signed anyone in through SSO, so off is how every install already behaved; while it is off Admin > Settings > SSO and every `/support/sso/*` route answer 404. To turn it on: run the migrations (`069` creates `escalated_sso_message_ids`), give the IdP the endpoints from the SSO page, make sure a SAML install has the IdP certificate, decide on `config.sso[:create_users]` and `[:sync_roles]`, then set the switch. See `docs/access-control.md`.
- `Escalated::Services::SsoService` is rewritten on `ruby-saml`, `oauth2` and `jwt` (new dependencies): `validate_saml_assertion` and `validate_jwt_token` are replaced by `validate_saml_response` and `validate_jwt`, which check far more (see below). The SSO settings page now validates the fields each provider needs and masks the OAuth client secret too.
- **SDK plugins can now be activated and deactivated, and only active ones run** (plugin contract, Lifecycle). Before, every SDK plugin the runtime loaded got every hook, cron schedule and badge, and its endpoints, webhooks and widgets were live, with no way to switch it off. The first time the runtime starts after upgrading, every SDK plugin installed at that moment is recorded active in `escalated_plugins`, so nothing that ran before stops. SDK plugins installed afterwards start inactive: activate them on **Admin > Plugins**. No migration is needed. Inactive SDK plugins get no hooks, cron or badges, add no widgets or slots, answer 404 on their endpoints and webhooks, and have their `ctx` calls refused (except `ctx.log`). `@escalated-dev/plugin-runtime` versions that honour the `plugins` list the host sends with `action` and `filter` run only active plugins' handlers; with older ones an inactive plugin's handler can still run but cannot read or write through `ctx`.
- Activating or deactivating a plugin from **Admin > Plugins** now answers with a 303 to the index and a `success` or `error` flash (it redirected back with `notice`/`alert`), and an unknown slug is an `error` flash (404 for JSON requests). The page receives `can_upload: true`. `Escalated::Plugin` slugs may now contain `--` and `_`, as the plugin contract's slugs do.
- **Two-factor authentication is now an install-level switch, off by default** (`config.access = { two_factor: true }`, env `ESCALATED_TWO_FACTOR`; ADR 2026-10-29-configurable-access-features). Nothing ever asked for the code, so off is how every install already behaved; while it is off the enrolment screen (`/support/admin/settings/two_factor*`) answers 404. To turn it on: run the migrations (`068` adds `last_used_step`), then set the switch. Users who enrolled before are challenged from their next visit. Set `ESCALATED_TWO_FACTOR_REQUIRED=true` (or the setting) only after telling staff. See `docs/access-control.md`.
- `POST /support/admin/settings` saves only the boolean settings a form sends; before, one left out was saved as off. The full Settings page sends every key, so it behaves as before.
- TOTP now uses the `rotp` gem (new dependency); new secrets are 32 base32 characters. Two-factor secrets and recovery codes are sealed at rest with a key derived from `secret_key_base`.
- **Roles & permissions is now an install-level switch, off by default** (`config.access = { roles_permissions: true }`, env `ESCALATED_ROLES_PERMISSIONS`; ADR 2026-10-29-configurable-access-features). Roles were stored but only the newsletter screens checked them, so off is how almost every install already behaved. While it is off:
  - The roles screens (`/support/admin/roles*`) answer 404.
  - The newsletter screens no longer check `newsletters.manage` / `newsletters.send` (they used the host's `roles` when it had any); the admin gate decides. Plugin UI items with a `permission` are shown to every staff user the gate admits. Installs that relied on these must turn the switch on.
  To enforce roles: `rake escalated:permissions:seed`, give every staff user a role (`rake "escalated:roles:assign[you@example.com,admin]"`), then turn the switch on. An admin without a role is refused everywhere but their own two-factor screen. See `docs/access-control.md`.
- The shared `escalated.permissions` prop is `['*']` for staff while the switch is off (it was the user's role slugs, which nothing enforced), and `escalated.features` carries `roles_permissions`, `two_factor` and `sso`.
- `db/seeds/permissions.rb` now loads its definitions from `lib/escalated/seeds/permissions.rb` (`Escalated::Seeds::Permissions`); running it does the same as before.
- **SDK plugin cron schedules run** when the host schedules `rake escalated:plugins:cron` every minute (cron, `whenever`, Solid Queue or sidekiq-cron). Without it, SDK plugins' `cron` handlers still never run.
- **Plugin UI extensions are shared as `escalated.plugins`** (`menuItems`, `pageComponents`, `dashboardWidgets`), the shape the shared frontend reads; before, they were shared as a top-level `plugin_ui` prop that no page read, so plugin menus, widgets and slots never appeared. Admin menu items go to admins only, items with a `permission` the viewer lacks are left out, and SDK plugins' `widgets` and `components` are included. With nothing to show, `escalated.plugins` is `{}`. The `plugin_ui` prop is gone.
- **Plugins receive the canonical domain events.** `ticket.created`, `reply.created`, `note.created`, `ticket.status_changed` and the rest of the event vocabulary go to Ruby plugins (`Escalated.hooks.add_action('ticket.created') { |payload| ... }`) and SDK plugins, with the payload of the plugin contract (the ticket flat and under `ticket`, plus the event's extras; replies flat plus `reply` and `ticket`). The Ruby hook names (`ticket_created`, `reply_added`, ...) still fire for Ruby plugins but are no longer forwarded to the SDK runtime, which now sees only dotted names. A raising plugin is logged and never fails the change.
- **`ctx.tickets.query` and `ctx.replies.query` only accept the plugin contract's filter keys.** Tickets: `id`, `reference`, `status`, `priority`, `channel`, `ticket_type`, `department_id`, `requester_id`, `contact_id`, `assigned_to`. Replies: `ticket_id`, `is_internal`, `type` (`reply`, `note` or `system`). Any other key, or a non-scalar value, raises instead of becoming a column name. Results are capped at 500 rows.

### Added
- **SDK plugin pages** (plugin contract, Pages): each `pages[]` entry of an active SDK plugin answers `GET {prefix}/admin/plugins/{slug}/{route}` behind the admin guard (and the page's `capability`, 403), rendering `Escalated/Plugin/Page` with `plugin`, `component`, `layout` (default `admin`) and `props` from the plugin's own `GET /{component}` endpoint (`{}` when it has none or it fails). An inactive or unknown plugin's page is a 404. Pages with a `menu` appear in `escalated.plugins.menuItems` (admin entries to admins only).
- **Admin > Users roles picker.** While roles & permissions is on, the users
  screen sends `roles` (`{id, name, slug}`, by name) and each user's role slugs,
  and `PUT /support/admin/users/:user_id/roles` (`{role_ids: [...]}`, needs
  `role.manage`) replaces a user's roles, as escalated-laravel's
  `escalated.admin.users.roles`. 404 while the switch is off.
- **Sign-in through SSO when switched on**, with the provider chosen in Admin > Settings > SSO (which now lists the endpoints for the IdP). SAML checks the assertion signature against the configured certificate, Issuer, Audience, Destination/Recipient, validity windows, InResponseTo against requests issued in the last 10 minutes, and replay; OAuth uses a session-bound state and PKCE; JWT pins the algorithm and requires `exp`, `aud` and a single-use `jti`. Users are matched by email, created only with `config.sso[:create_users]`, and given the asserted role only with roles on and `[:sync_roles]`.
- **SDK plugins on Admin > Plugins**: listed by slug with `name`, `version`, `description`, `is_active`, `activated_at`, `source: composer` and `provides` counts; activating sends the runtime `activate {plugin}` and deactivating `deactivate {plugin}` (`PluginBridge#activate` / `#deactivate`); uninstalling is refused (npm manages them).
- **Lifecycle actions `plugin.activated`, `plugin.deactivated` and `plugin.uninstalling`** with `{plugin, slug}`, to Ruby and SDK plugins, in the contract's order. A raising callback is logged and does not undo the transition.
- **Two-factor authentication is enforced when switched on.** A staff user with a confirmed enrolment must pass `Auth/TwoFactorChallenge` (`/support/two-factor/challenge`; TOTP code or single-use recovery code; replayed codes refused; 5 attempts per minute) in their session before any admin or agent page; JSON requests get `403 {two_factor_required: true}`. Enrolment is open to agents as well as admins. Admins can require enrolment (`config.two_factor[:required]` or the `two_factor_required` setting), and `rake escalated:two_factor:reset[user]` clears a lost device. Pages get `escalated.two_factor_required`.
- **Roles & permissions are enforced when switched on.** Every admin, agent and staff API action needs its permission from the user's Escalated roles as well as the host gate (`lib/escalated/support/route_permissions.rb`; unmapped actions are refused and a spec checks every route is mapped). Status changes to `resolved`/`closed`/`reopened` also need `ticket.close`, bulk actions need each action's permission, internal API replies need `reply.create_internal`, and API tokens are checked as their owner. Failing answers 403.
- `rake escalated:permissions:seed` and `rake "escalated:roles:assign[user,role]"`.
- SDK plugin cron schedules: `rake escalated:plugins:cron` sends each five-field (UTC) schedule of each SDK plugin that is due that minute to the plugin runtime as `cron`, as no user, within 30 s; an unreadable schedule is logged and skipped, and a failing one never stops the others.
- SDK plugin widget badges: widgets with a `badge` function carry its answer in `escalated.plugins.dashboardWidgets[].badge`, asked as the viewer (`ctx.currentUser` is the signed-in user for that call) within 5 s, `null` when it fails.

### Fixed
- SDK plugin endpoints answered 500 on every call: the controller called `to_unsafe_h` on the query parameters, which are a plain hash.

### Security
- Plugin ticket and reply queries passed the filter's keys to `where` as column names, so an SDK plugin could filter on any column (such as the guest access hash). Keys are now whitelisted.
- `ctx.emit` drops hook names that would impersonate a canonical event, a legacy alias of one, or a plugin lifecycle action.

## [0.7.6] - 2026-10-28

### Upgrading
- `POST /widget/chat/start` now answers exactly as escalated-laravel: `201
  { id, session_id, expires_at, ticket_reference, status, agent_name }` with
  `id` and `session_id` both the chat token (plus `customer_session_id`,
  `messages` and `agent`). The numeric `session_id` and `ticket_id` are no
  longer returned; use `id` for the widget chat routes and `ticket_reference`
  to name the ticket.
- Run `bin/rails db:migrate`: migration 067 adds a nullable
  `customer_token_expires_at` to `escalated_chat_sessions`. Chats already in
  progress keep working: the next widget request with their token stores the
  token's hash in place of the plain value and gives it a full lifetime.
- Widget chat tokens now expire `guest_access_ttl_minutes` after the chat
  starts (default 1440, clamped to 5 minutes .. 7 days), as in
  escalated-laravel. After that every `/widget/chat/:token/*` route answers 404
  and the visitor starts a new chat.
- `ChatSessionService.start_chat` no longer accepts a caller-chosen
  `session_id`; the token is always random. Read it once from
  `result[:session].visitor_token`. `customer_session_id` now holds its
  SHA-256, so agent payloads and broadcasts no longer carry the visitor's token.

### Added
- **Mobile guest API.** While `api_enabled` is on, five JSON routes under
  `<api_prefix>/mobile/guest` (default `/support/api/v1/mobile/guest`) let a
  mobile app file, read and reply to a guest ticket:
  `POST verification`, `POST lookup`, `POST tickets`, `GET tickets/:token` and
  `POST tickets/:token/replies`, per the canonical contract
  (escalated-developer-context `domain-model/mobile-guest-api.md`). They reuse
  the guest pages' and widget's email codes, grants, verification and lookup
  handlers and per-IP guest budgets, so a grant from any surface works on the
  others. Hosts with `api_enabled` off get no new routes.
- `guest_rate_limit` has a `requests_per_minute` budget (default 60), counted
  on every mobile guest request.

### Fixed
- `POST /widget/verification` and `POST /widget/lookup` were not counted
  against the per-IP guest budgets: the widget's own ticket throttle replaced
  the shared one (Rails keeps one callback per method name). Widget code
  requests now count as submissions and widget lookups as replies, as the
  guest pages' always did.

### Security
- **Widget chat tokens are stored hashed and expire.** The token returned by
  `POST /widget/chat/start` (`id`, also `customer_session_id`) was stored in
  plain text and never expired. Only its SHA-256 is stored now, the start
  response carries `expires_at`, and an unknown or expired token is a 404 on
  every chat route. The guest's websocket chat check uses the same lookup.

### Changed
- An ended chat answers 422 to `typing` (was 204) and to a second `end` (was
  200), and `rate` answers 422 until the chat has ended, as in
  escalated-laravel. Its transcript (`ended: true`) and rating stay available
  until the token expires.

## [0.7.5] - 2026-10-22

### Fixed
- **Chat transfer reads `department_id`.** `POST /admin/chat/:id/transfer`
  took only `agent_id`, so the shared ticket view's Transfer menu (which offers
  departments and posts `{"department_id"}`) was refused with 422. It now reads
  `agent_id` and/or `department_id`, as escalated-laravel does: a department
  takes the ticket, and without an agent the chat goes back to the queue
  (unassigned, waiting) and is routed again for that department. The older
  `{"type", "id"}` body is read too, and `agent_id` alone behaves as before.
  An unknown department, or an agent who cannot see the ticket, is a 422 (the
  latter was a 500). `ChatSessionService.transfer_chat(session, agent_id = nil,
  department_id: nil)` keeps its positional agent argument.

## [0.7.4] - 2026-10-22

### Upgrading
- Run the migrations. `066_add_user_id_to_escalated_import_jobs` adds a nullable `user_id` column.
- An import job written under Active Record encryption reads back with no credentials. Cancel and restart a paused one.
- The import screens moved to Laravel's paths. The `/admin/imports` routes still answer; their pause, resume and start redirect to the new Progress path. The Progress page no longer receives `adapters`, which it does not read.
- `GET /admin/custom_objects/:id/records` now renders the Records page. Send `Accept: application/json` to keep getting the JSON list.
- The record actions answer an Inertia request with a redirect back to the Records page. Other requests still get JSON.
- The old nested bodies (`ticket_status`, `role`, `business_schedule`) still work.
- The CSAT screen renders `Settings/CsatSettings` with `csat_question_text`, `csat_scale`, `csat_delivery_trigger` and `csat_delay_hours`. The old `Settings/Csat` name had no component in the frontend, and its keys (`csat_enabled`, `csat_send_after_hours`, `csat_message`) were read nowhere, so they are no longer shown or saved.
- Retention purges are permanent: tickets have no soft delete in this engine, so where Laravel soft-deletes a closed ticket and removes it 30 days later, `PurgeExpiredDataJob` destroys it with its replies, attachments, activities and workflow logs. Try `rake escalated:purge_expired DRY_RUN=1` first.
- Saving a webhook with the secret left blank (or left out) keeps the stored secret, as before, because the form never receives it. Send `clear_secret: true` to remove it.
- The SSO settings page receives `sso_jwt_secret` as the mask `********` ('' when unset) and posts it back for a secret the admin did not change; a posted mask is ignored and any other value replaces the stored secret, as before. The general settings page now masks the Mailgun signing key, Postmark inbound token and IMAP password as `********`; the older `abc*****` mask is still recognised when posted back.
- `Escalated::Webhook`, `ImportJob`, `TwoFactor` and `ApiToken` leave their secrets out of `as_json`/`to_json`/`serializable_hash` (and `inspect`). Host code that serialized one of these models and read the secret from the result must read the attribute directly. `Webhook#as_json` carries `has_secret`.

### Added
- The admin Import wizard, on escalated-laravel's routes and props: `Admin/Import/Index` (`GET /admin/import`), `Connect` (`GET /admin/import/:platform/connect`, with `POST .../test-connection` answering `{ success[, error] }`), `Mapping` (`GET .../mapping`), `Review` (`POST .../review`, which writes nothing), `start` (`POST .../start`), and `Progress` (`GET /admin/import/progress/:job_id`, polled through `GET /admin/import/status/:job_id`, with `POST /admin/import/{pause,resume,cancel}/:job_id`). Sources are still the adapters registered on the `import.adapters` filter; core ships none. Tested credentials wait in the session, encrypted, until the import starts, and are never sent to the browser.
- `Escalated::RunImportJob` runs an import on the `escalated` queue. The `import.run_async` action still replaces it.
- Import jobs record the admin who started them (`user_id`).
- `Admin/Settings/DatabaseConnection` at `GET /admin/settings/database`. It shows the connection Escalated's tables use and every connection in `database.yml`, each probed for whether it is reachable, carries Escalated's tables, and how many tickets it holds. `POST /admin/settings/database/test` probes one. The connection is still set only by `config.database_connection`, so the screen is read-only, like Laravel's when the connection is pinned by config. `POST /admin/settings/database` is refused.
- The report pages `Reports/AgentMetrics`, `SlaReport`, `CsatReport` and `AgentDetail`, at `GET /admin/reports/agents`, `/sla`, `/csat` and `/agent/:id/detail` (Laravel's paths), with the props escalated-laravel sends. AgentDetail sends what the component declares: this period against the one before, response-time percentiles, and daily productivity and workload. Each takes the period as `days` (default 30).
- The admin Form pages for statuses, roles, business hours, custom fields and custom objects, plus the custom object Records page, now render with the props escalated-laravel sends them. New routes: `GET /admin/{statuses,roles,business_hours,custom_fields,custom_objects}/new` and `/:id/edit`, and `POST /admin/custom_objects/:id/records`.
- The knowledge base pages: the admin article form (`GET /admin/articles/new` and `/:id/edit`) and the customer reader, `Customer/KnowledgeBase/Index` and `Article` (`GET /customer/kb`, `GET /customer/kb/:slug`, `POST /customer/kb/:slug/feedback`). Props and behaviour follow escalated-laravel. Only published articles are shown, and each read counts a view. A disabled knowledge base answers 404. A private one answers 403 to signed-out visitors. Feedback answers 404 while it is turned off.
- The settings pages `Admin/Settings/CsatSettings` (`GET`/`POST /admin/settings/csat`), `DataRetention` (`/admin/settings/data-retention`) and `EmailSettings` (`/admin/settings/email`), with escalated-laravel's props and validation, stored in the settings table. As in Laravel, the CSAT and email settings are stored only: surveys are not sent from them, and outbound mail keeps its configured from address.
- `Escalated::PurgeExpiredDataJob` and `rake escalated:purge_expired` (`DRY_RUN=1` only counts) apply the data retention settings: closed tickets closed before the cutoff, attachments and audit logs created before theirs, and expired guest verification codes. Every retention defaults to `never`, so it purges nothing else until an admin picks a period. Schedule it daily (see the README).

### Fixed
- Imports never ran from the admin screens. The plugin bridge registers a callback on every documented action, `import.run_async` included, so the engine always handed the run to that hook, which only forwarded it to the Node runtime.
- Saving an import job raised in an app without Active Record encryption keys. Its credentials are now encrypted with a key derived from `secret_key_base`.
- An imported ticket with no description failed validation. It now falls back to the subject, as Laravel's tickets need no description.
- Import mode now also holds back @mention notifications for imported replies, SLA policy attachment and breach checks, escalation rules and automations, as Laravel's ImportContext does.
- `Reports/Dashboard` rendered every tab empty. It was sent today/this-week counts under names the component does not declare. It now gets Laravel's props: `volume`, `by_status`, `by_priority`, average response and resolution hours, `sla_compliance`, `csat_average` and `agent_performance`, over `days`.
- The roles, business hours and custom objects lists failed with a 500 error. The custom fields and custom objects screens, and the role list, read and wrote columns these tables do not have.
- These screens now take the bodies the shared forms post: fields at the top level, role `permissions`, schedule `holidays` with `recurring`, custom field `type`, and custom object `slug` and `fields_schema`. They are validated the way escalated-laravel validates them. A refused save goes back to the form with the errors on their fields.
- The article admin takes the body the shared form posts. A blank slug is derived from the title. Publishing stamps `published_at` once. The list sends `view_count`, `helpful_count` and `category_id`, and no longer sends `statuses`, which the page does not read.
- The admin flash messages for statuses, roles, business hours, custom fields, custom objects and articles had no English text.
- `Admin/Settings/PublicTickets` saves from the `POST` the page sends (PUT still works), at Laravel's path `/admin/settings/public-tickets`, and validates like Laravel: a guest-user policy needs a user, and an unknown mode is refused with the error on its field. The old `/admin/settings/public_tickets` path still works.

### Security
- **Stored secrets are no longer sent to admin pages.** The SSO settings page received `sso_jwt_secret` in full, and the general settings page showed the first three characters of the Mailgun signing key, Postmark inbound token and IMAP password. Both now show only the mask `********`. The models that store secrets (`Webhook` `secret`, `ImportJob` `credentials`, `TwoFactor` `secret` and `recovery_codes`, `ApiToken` `token` hash) now leave them out of serialization, so a page or JSON response built from the model cannot carry them; the import run and webhook signing still read them server-side. The import and webhook pages already sent explicit field lists without these secrets; the import pages now build theirs from `ImportJob#to_page_props` and send at most the last 50 errors. Webhook updates accept `clear_secret: true`.

## [0.7.3] - 2026-10-21

### Upgrading
- Run the migrations. `065_add_verified_guest_access` adds four nullable ticket columns and a `guest_verifications` table.
- Configure outbound mail and a shared `Rails.cache` (Redis or Memcached) across processes.
- Use the bundled widget or `@escalated-dev/escalated` 0.12.3 or later. Older clients cannot create guest tickets or start chats without the code step.
- Existing permanent guest links keep working while `accept_legacy_guest_tokens` is on (the default for now), until a grant is issued for the ticket. Set it to `false` to retire them. Guests can get a new link through lookup.
- `Ticket#guest?` now also treats a ticket with a guest email and no requester as a guest.
- Old `rails_blob_path` links do not expire. If the host does not use ActiveStorage's own routes for anything else, set `config.active_storage.draw_routes = false` to retire them. Keep cloud buckets private.
- `AttachmentService.url_for` returns the new route. Its `expires_in:` keyword is replaced by `guest_ticket:`.
- Nothing to migrate. Workflows stored with `ticket.replied` and webhook subscriptions stored with `internal_note.added`, `tag.added`, `ticket.tagged`, `tag.removed`, `ticket.untagged`, `chat.session_started` or `chat.session_ended` keep working: they are read as their canonical names, shown in the admin forms under those names, and rewritten to them the next time they are saved.
- A receiver that matched `internal_note.added` in the `X-Escalated-Event` header or the `event` field should match `note.created` instead.

### Security
- Verified guest access ([docs/guest-access.md](docs/guest-access.md)), as in escalated-laravel.
  - Guest tickets, widget tickets, live chats and ticket lookups need an emailed 8-digit code:
    - it expires after 10 minutes and allows 5 guesses
    - it can be used once
    - sending is limited to 3 codes an hour per mailbox and client IP, and 10 an hour per mailbox
  - New routes: `POST /guest/verification`, `POST /guest/lookup`, `POST /widget/verification` and `POST /widget/lookup`.
  - New tickets get an expiring grant instead of a permanent `guest_token`.
    - The ticket stores only a hash of it.
    - It lasts `guest_access_ttl_minutes`, default 1440.
    - Rotating it, or changing the guest email, revokes it and the attachment links issued under it.
  - The widget create response returns `guest_access_token` and `expires_at` instead of `guest_token`.
  - The widget status view reads `GET /widget/tickets/:reference` with `Authorization: Bearer <grant>`.
  - `/widget/config` sends `guest_verification_required: true` and `status_lookup_enabled: true`.
  - Guest/Create receives `verification_url` and `lookup_url`.
  - Guest and widget responses carry `Cache-Control: no-store` and `Referrer-Policy: no-referrer`.
- Attachments are private ([docs/private-attachments.md](docs/private-attachments.md)).
  - Every screen and the API link to a signed download route, `GET /support/attachments/:id?token=...`, which expires after `attachment_download_ttl_minutes` (default 10, 1 to 60). It replaces `rails_blob_path` and presigned storage URLs, which skipped the ticket-access check.
  - The download needs current access:
    - agents and admins who can see the ticket
    - the requester, except for internal-note files
    - a guest, through a capability on the guest page's links that is bound to the ticket's guest token
  - Downloads are sent as `attachment` with a sanitised name, `nosniff` and `private, no-store`. Types other than PNG, JPEG, GIF, WebP and PDF are sent as `application/octet-stream`.
  - API replies now include each attachment's `url`.

### Fixed
- The guest form reads the `guest_name` and `guest_email` fields Guest/Create posts. It still reads `name` and `email`.

### Changed
- One event vocabulary for webhooks and workflow triggers (escalated-developer-context ADR 2026-10-21). See `Escalated::EventNames`.
  - Internal notes are sent to webhooks as `note.created` (was `internal_note.added`).
  - The workflow reply trigger is `reply.created` (was `ticket.replied`), and it fires on public replies only. An internal note fires `note.created`. Before, a `ticket.replied` workflow also ran on internal notes.
  - Workflows can now be triggered by every event the engine emits: `ticket.updated`, `ticket.unassigned`, `ticket.department_changed`, `ticket.resolved`, `ticket.closed`, `ticket.reopened`, `ticket.tag_added`, `ticket.tag_removed`, `note.created` and the chat events, as well as the ones offered before.
- Live chat emits `chat.started`, `chat.assigned`, `chat.transferred`, `chat.message` and `chat.ended` to webhooks and workflows. The payload carries the chat session's `id`, never the visitor's session token.

## [0.7.2] - 2026-10-20

### Changed
- The bundled widget is now `@escalated-dev/escalated` 0.12.3. It keeps its script settings when `embed.js` is placed in the page `<head>`, and Enter no longer picks a stale mention suggestion.

### Security
- The widget and widget chat skip CSRF only for requests from an allowed embedding site (`widget_allowed_origins`). A tokenless POST from any other origin, or from the same origin, is now refused, as with Laravel's `WidgetCsrf`.
- The widget's article endpoints honour the knowledge-base switches: 404 while the knowledge base is off, 403 to a guest while it is not public. `/widget/config` reports `kb_enabled` the same way.

### Fixed
- Widget tickets keep the visitor's name, email, contact and a guest token. `LocalDriver#create_ticket` dropped those fields, so every widget ticket was saved anonymous and the widget got `guest_token: null`. The `guest_user` policy mode is applied too.
- Guest-portal and live-chat tickets go through `TicketService`, so they get an SLA and emit `ticket_created` (workflows, webhooks, notifications, broadcast).
- Ticket screens get the props the pages read: `ticket.replies` (and `ticket.activities`) on Customer, Agent and Admin ticket show, `tickets.data` on every ticket list, `cannedResponses`, `assigned_to`, and the SLA due dates under the names the sidebar reads.
- Customer routes: `GET /customer/tickets` rendered the create form instead of the list, and `POST /customer/tickets` rendered the form instead of saving. The form is at `/customer/tickets/create` (and `/new`), and customer tickets are found by reference.
- Widget chat checks `widget_enabled` and a new `chat_enabled` setting (on by default), applies the guest submission and reply throttles, and answers 422 JSON for an empty message or an ended chat.
- `TicketService.unassign` emits `ticket_unassigned`. Webhooks now send `ticket.unassigned`, `ticket.updated`, `ticket.department_changed`, `ticket.tag_added`, `ticket.tag_removed` and `sla.warning`.
- UUID and string user keys: migration 064 moves `department_agents.agent_id` and `chat_sessions.agent_id` to `Escalated.user_id_type` (no-op on bigint hosts), and the `add_follower` workflow action no longer casts the user id to an integer.

## [0.7.1] - 2026-10-19

### Changed
- The bundled widget is now `@escalated-dev/escalated` 0.12.2. It hides its Check Status tab when `/config` returns `status_lookup_enabled: false`.

### Security
- Widget chat start no longer accepts a client-supplied `session_id`. The chat token is always generated by the server, so a visitor cannot pick a token that matches another session.

### Fixed
- The widget API now matches the shared widget. `/widget/config` lists the
  active `departments` and sends `guest_tickets_enabled` and
  `status_lookup_enabled: false`, and answers 403 with `enabled: false` while
  the widget is off. `/widget/articles` returns `{ articles: [...] }` instead of
  a bare array. Widget tickets and chats file into the chosen `department_id`
  (unknown or inactive departments get a 422 with `errors.department_id`).
  `/widget/chat/start` returns `id`, the chat's random customer token, and the
  chat adds `GET`/`POST /widget/chat/:id/messages`; the older
  `/widget/chat/:id/message` route still works.
- Preserve trailing spaces in account visibility and list filters on MySQL and MariaDB.

### Added

- Embed the widget, ticket form and live chat on other sites. List the
  embedding sites in `config.widget_allowed_origins`
  (`ESCALATED_WIDGET_ALLOWED_ORIGINS`) or the `widget_allowed_origins` admin
  setting; `https://*.example.com` subdomain wildcards are supported. Widget
  requests from a listed origin get CORS headers (including on 403, 404, 422
  and 429 answers) and always run as a guest. Requests from any other origin
  are handled exactly as before. Empty by default. See
  `docs/embedding-the-widget.md`.
- `GET {route_prefix}/widget/embed.js` serves the standalone widget bundle
  built from `@escalated-dev/escalated` 0.12.1; `config.widget_serve_script`
  turns the route off.
- Widget tickets and live chats keep host parameters sent as `metadata`,
  sanitised to a flat map of short scalar values, plus a server-recorded
  `embedded_on` origin. `/widget/config` advertises `accepts_metadata: true`.
- The admin settings screen saves the widget switch, colour, position and
  greeting it already showed; they were dropped before.
- Opt-in department/account ticket access across queries, policies, API, bulk
  actions, reports, widgets, notifications and chat subscriptions.
- Nullable account identities and host resolvers; type/account routing conditions.
- Optional department/type SLA targets with deterministic selection.

### Fixed

- API bearer tokens use the hashed token lookup; bulk actions read the submitted
  action instead of the Rails route action.


## [0.7.0] - 2026-10-08

### Upgrading

- **Inbound email works again.** Provider webhooks answered 500 in 0.6.x
  because the mail adapters were never loaded. Check your provider's webhook
  logs after upgrading; mail sent while it was broken was not stored.
- **Only the requester can reply by email.** A matched message is a reply only
  when `From` is the ticket's guest email or `requester.email`
  (case-insensitive), and it is posted as the requester. Mail from anyone else,
  an agent's address included, opens a new ticket, so agents reply in the app.
- **Set `config.email_inbound_secret`.** With it set, only the signed Reply-To
  address links mail to a ticket; `In-Reply-To`, `References` and subject
  references no longer do.
- **Accepted email replies reopen resolved and closed tickets.**
- **Guest endpoints are rate-limited per client IP** (5 tickets and 10 replies
  a minute) through `config.guest_rate_limit`. Behind a proxy, set
  `config.action_dispatch.trusted_proxies` or every guest shares one limit. Use
  a shared `cache_store` when you run more than one process.

### Added
- **Per-IP rate limit on guest ticket creation and replies.** The widget and guest-form ticket
  endpoints allow 5 submissions and the guest reply endpoint 10 replies per client IP per minute,
  counted separately; over the limit the response is `429` with `Retry-After`. The reply limit is
  checked before the guest token, so wrong-token requests count. Configure with
  `config.guest_rate_limit` (`enabled`, `tickets_per_minute`, `replies_per_minute`, `cache_store`).
  The client IP is `request.remote_ip`: behind a proxy, set `config.action_dispatch.trusted_proxies`
  or all guests share one limit.

### Fixed
- **Inbound email webhooks load their adapters.** Nothing required `lib/escalated/mail`, so every
  provider webhook answered 500.
- **Inbound replies come only from the ticket's requester.** With `email_inbound_secret` set, only
  the signed Reply-To address links mail to a ticket. A matched email is a reply only when `From`
  is the ticket's guest or requester email, and it is posted as the requester; any other sender
  gets a new ticket. Accepted replies reopen resolved or closed tickets.

## [0.6.4] - 2026-09-15

### Added
- **Cloud → site webhook receiver.** `POST /support/cloud/webhook` applies `ticket.updated` and
  `ticket.status_changed` from cloud.escalated.dev to the local ticket (matched by `reference`),
  verified with the new `hosted_signing_secret` and deduplicated by `event_id`. Synced mode is
  now two-way, as it already was for the Laravel package (v1.8.4).

## [0.6.3] - 2026-09-15

### Fixed
- **Synced mode never reached the cloud.** `HostedApiClient.emit` posted to
  `/sync/<action>`, routes cloud.escalated.dev does not serve, so every event
  from the `SyncedDriver` was a 404 that the driver logged and dropped. Actions
  are now mapped to the cloud's event names (`ticket.created`,
  `ticket.status_changed`, `reply.created`, ...) and posted to `POST /events`
  with a stable `event_id` and timestamp. The ticket payload also carries
  `requester_name` so the cloud projection shows who asked.

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
