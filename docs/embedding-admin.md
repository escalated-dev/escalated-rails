# Embedding the admin in your own admin panel (optional)

Escalated ships a complete standalone admin at `/support/admin` (your
`config.route_prefix` + `/admin`), with its own sidebar and top bar. **That is
the default, and it needs no setup.** If your Rails app already has an admin
panel, you can instead show Escalated's admin screens inside it: under your
sidebar and header, your URL prefix and your guards.

This is an optional alternative to the standalone admin. Nothing on this page
has any effect until you turn it on: with no embed configuration every route,
guard, page, prop, layout and header is exactly what it was before (a spec
compares the whole route table, with each route's `before_action` guards,
against a snapshot taken before this feature existed). The design is in the ADR
[`2026-11-05-embeddable-admin`](https://github.com/escalated-dev/escalated-developer-context/blob/main/decisions/2026-11-05-embeddable-admin.md);
the frontend side is documented in
[`@escalated-dev/escalated` docs/embedding-admin.md](https://github.com/escalated-dev/escalated/blob/main/docs/embedding-admin.md).

## Contents

- [Pick your setup](#pick-your-setup)
- [Turning it on](#turning-it-on)
- [Configuration reference](#configuration-reference)
- [What changes, and what does not](#what-changes-and-what-does-not)
- [1. Vue + Inertia host](#1-vue--inertia-host)
- [2. Server-rendered host (ERB layout)](#2-server-rendered-host-erb-layout)
- [3. iframe](#3-iframe)
- [The admin menu: `escalated.navigation`](#the-admin-menu-escalatednavigation)
- [Security](#security)
- [Turning it off](#turning-it-off)

## Pick your setup

| Your admin panel | Use | `mode` |
|---|---|---|
| Inertia + Vue in this app | [Vue + Inertia host](#1-vue--inertia-host) | `layout` |
| ERB (or other server-rendered) layouts | [Server-rendered host](#2-server-rendered-host-erb-layout) (your layout as the root view) | `layout` |
| Another app or origin, a non-Vue SPA, a CMS admin | [iframe](#3-iframe) | `iframe` |

## Turning it on

Call `config.embed_admin` in `config/initializers/escalated.rb` (it must run
before the routes are drawn, which an initializer does):

```ruby
# config/initializers/escalated.rb
Escalated.configure do |config|
  config.embed_admin(
    prefix: 'admin/support',
    middleware: [:authenticate_user!, -> { head :forbidden unless current_user&.admin? }],
    layout: 'Layouts/AdminLayout'
  )
end
```

or set the hash yourself (keys you leave out keep their defaults):

```ruby
Escalated.configure do |config|
  config.embed = {
    enabled: true,                       # ESCALATED_EMBED
    mode: 'layout',                      # ESCALATED_EMBED_MODE
    prefix: 'admin/support',             # ESCALATED_EMBED_PREFIX
    middleware: [:authenticate_user!],
    replace_admin_gate: false,
    layout: 'Layouts/AdminLayout',
    root_view: nil,
    frame_ancestors: []                  # ESCALATED_EMBED_FRAME_ANCESTORS
  }
end
```

or, with no code, the env vars `ESCALATED_EMBED=true`,
`ESCALATED_EMBED_MODE`, `ESCALATED_EMBED_PREFIX` and
`ESCALATED_EMBED_FRAME_ANCESTORS`. Restart the server after changing it; the
routes are drawn from it at boot. Embedding needs the screens
(`config.ui_enabled`, on by default).

## Configuration reference

| Key (`config.embed[...]`) | Env var | Default | Meaning |
|---|---|---|---|
| `enabled` | `ESCALATED_EMBED` | `false` | Master switch. While `false`, nothing below has any effect. |
| `mode` | `ESCALATED_EMBED_MODE` | `'layout'` | `'layout'` (Vue + Inertia or server-rendered host) or `'iframe'`. |
| `prefix` | `ESCALATED_EMBED_PREFIX` | `'admin/support'` | URL prefix the admin moves under. |
| `middleware` | | `nil` | Your guards for the admin routes, in order: `before_action` method names (`:authenticate_user!`) or blocks run in the controller (`-> { head :forbidden unless current_user&.admin? }`, or `->(controller) { ... }`). The first that renders or redirects stops the request. `nil` keeps `config.middleware`, as every Escalated screen does today. |
| `replace_admin_gate` | | `false` | `true` removes Escalated's admin gate from these routes so your `middleware` alone decides. Refused without `middleware`. See [Security](#security). |
| `layout` | | `nil` | Name of your Vue admin layout, matched against the frontend plugin's `layouts` option. |
| `root_view` | | `nil` | Layout template for embedded pages ([server-rendered host](#2-server-rendered-host-erb-layout)), e.g. `'admin/escalated'` for `app/views/layouts/admin/escalated.html.erb`. |
| `frame_ancestors` | `ESCALATED_EMBED_FRAME_ANCESTORS` (comma-separated) | `[]` | iframe mode: exact origins allowed to frame the admin. Wildcards, `*`, paths and non-http(s) entries are dropped. |

`config.embed_admin` (also `Escalated.embed_admin`) takes the same settings as
keyword arguments: `prefix:`, `middleware:`, `layout:`, `root_view:`, `mode:`,
`replace_admin_gate:`, `frame_ancestors:`, and raises for an unknown `mode` or
for `replace_admin_gate: true` without `middleware`.

A method name in `middleware` must be a method of
`Escalated::ApplicationController`, which inherits from
`ActionController::Base`, not from your `ApplicationController`. Devise's
`authenticate_user!` / `authenticate_admin!` are; a check of your own is best
written as a block. A method name it does not have raises instead of being
skipped, so a misspelt guard can never silently let everyone in.

## What changes, and what does not

While embedding is on:

- The engine is mounted at the root and draws `route_prefix` itself, so every
  URL outside the admin stays where it was.
- Every admin screen that lived under `/support/admin` (tickets, settings,
  reports, plugins, API tokens, import, chat and the rest) and the SDK plugins'
  admin pages (`/support/admin/plugins/{slug}/...`) are drawn under your
  `prefix` instead. They run your `middleware` in place of
  `config.middleware`, then Escalated's own checks (`require_admin!`: the admin
  gate unless you replace it, two-factor and route permissions). **Route
  names and handlers do not change**, so `escalated.admin_tags_path` and the
  frontend's `route('escalated.admin.…')` (the `ziggy` prop) follow the move.
  The old `/support/admin/...` URLs answer 404.
- Every Inertia page carries `escalated.navigation`, the admin menu for your
  sidebar, and `escalated.embed` (below).

Unchanged: the agent panel (`/support/agent`), customer portal, guest pages,
widget, the JSON API, SDK plugin endpoints and webhooks, SSO, the two-factor
enrolment page (`/support/admin/settings/two_factor`, personal to every staff
user) and challenge, and the newsletter admin (`/support/admin/newsletters`).

`escalated.embed` on an embedded page:

```json
{
  "enabled": true,
  "mode": "layout",
  "layout": "Layouts/AdminLayout",
  "route": "escalated.admin.tickets.index",
  "base_url": "/admin/support",
  "allowed_origins": []
}
```

On every other page `enabled` is `false` and `route` is `null`. `route` is the
frontend's name for the page (the `ziggy` route list), not the Rails route
helper name.

## 1. Vue + Inertia host

Backend: turn embedding on (above) with your prefix and admin guards.

Frontend (`app/javascript/entrypoints/application.js`): register your admin
layout under the name you gave `layout`:

```js
import { createApp, h } from 'vue'
import { createInertiaApp } from '@inertiajs/vue3'
import { EscalatedPlugin } from '@escalated-dev/escalated'
import AdminLayout from '../layouts/AdminLayout.vue'
import AppLayout from '../layouts/AppLayout.vue'

createInertiaApp({
  resolve: (name) => { /* the resolver from the README's Page Resolver section */ },
  setup({ el, App, props, plugin }) {
    createApp({ render: () => h(App, props) })
      .use(plugin)
      .use(EscalatedPlugin, {
        layout: AppLayout,                               // customer pages, as before
        layouts: { 'Layouts/AdminLayout': AdminLayout }, // embedded admin pages
        theme: { panel: { mode: 'light' } },             // match your admin
      })
      .mount(el)
  },
})
```

Your admin layout needs the same slots the plugin's `layout` always required, a
`#header` slot (Escalated puts the page title there) and a default slot. List
Escalated's menu with `<EscalatedNavigation />`:

```vue
<!-- app/javascript/layouts/AdminLayout.vue -->
<script setup>
import { Link } from '@inertiajs/vue3'
import { EscalatedNavigation } from '@escalated-dev/escalated'
</script>

<template>
  <div class="flex min-h-screen">
    <aside class="w-64 border-r bg-white p-3">
      <Link href="/admin">Dashboard</Link>
      <!-- …your own items… -->
      <p class="mt-4 px-3 text-xs font-semibold uppercase text-gray-500">Support</p>
      <EscalatedNavigation />
    </aside>
    <div class="flex-1">
      <header class="border-b bg-white px-6 py-4"><slot name="header" /></header>
      <main class="p-6"><slot /></main>
    </div>
  </div>
</template>
```

Escalated renders each admin page chrome-free (no Escalated sidebar, top bar,
logo or footer) inside your layout. To use the same layout for customer pages
too, use `layout: AdminLayout, layoutScope: ['customer', 'admin']` instead of
`layouts`. `useEscalatedNavigation()` gives the same items as computed refs if
you draw the menu yourself.

## 2. Server-rendered host (ERB layout)

If your admin chrome is an ERB layout, make a layout that contains it and
yields the Inertia page, and point `root_view` at it:

```ruby
# config/initializers/escalated.rb
Escalated.configure do |config|
  config.embed_admin(
    prefix: 'admin/support',
    middleware: [:authenticate_user!, -> { head :forbidden unless current_user&.admin? }],
    root_view: 'admin/escalated'
  )
end
```

```erb
<%# app/views/layouts/admin/escalated.html.erb %>
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <%= csrf_meta_tags %>
  <%= escalated_route_helper_tag %>
  <%= vite_client_tag %>
  <%= vite_javascript_tag 'application' %>
</head>
<body>
  <header>Host admin</header>
  <aside data-host-admin-sidebar>
    <p class="menu-heading">Support</p>
    <ul>
      <% escalated_admin_navigation.each do |item| %>
        <li><a href="<%= item[:url] %>"<% if item[:active] %> class="active" aria-current="page"<% end %>><%= item[:label] %></a></li>
      <% end %>
    </ul>
  </aside>
  <main><%= yield %></main>
</body>
</html>
```

This is the layout `spec/dummy/app/views/layouts/host_admin.html.erb` the specs
render, plus your asset tags. `yield` is where the Inertia page (`<div
data-page=...>`) goes. Only embedded pages use this layout; the rest of
Escalated keeps your normal one. Your Inertia entry needs no extra option:
Escalated sees `escalated.embed.enabled` and renders the page chrome-free
(title + content). `escalated_admin_navigation` is available in every view
(your own admin pages too) and is `Escalated.admin_navigation(current_user,
request)`. A custom `Escalated.ui_renderer` must apply `root_view` itself.

## 3. iframe

For an admin that is not part of this app (another origin, another stack),
frame the embedded admin:

```ruby
Escalated.configure do |config|
  config.embed_admin(
    prefix: 'admin/support',
    middleware: [:authenticate_user!],
    mode: 'iframe',
    frame_ancestors: ['https://admin.example.com']
  )
end
```

or `ESCALATED_EMBED=true`, `ESCALATED_EMBED_MODE=iframe`,
`ESCALATED_EMBED_FRAME_ANCESTORS=https://admin.example.com`.

Embedded responses then carry
`Content-Security-Policy: frame-ancestors 'self' https://admin.example.com`
and no `X-Frame-Options` (the allow-listed `frame-ancestors` replaces Rails'
default `SAMEORIGIN` on those responses only). Escalated inserts a small Rack
middleware, `Escalated::EmbedFrameHeaders`, at the top of your stack while
embedding is on, so this happens after every other middleware (including
`secure_headers` or anything else that sets `X-Frame-Options`). If your app
already sends a CSP (`config/initializers/content_security_policy.rb`), it is
kept and this directive is added as a second policy; if your own policy has a
`frame_ancestors` directive, add the same origins there too, since browsers
enforce both.

On the framing page:

```html
<iframe id="support-admin" src="https://support.example.com/admin/support/tickets"
        style="width:100%;border:0" title="Support administration"></iframe>
<script type="module">
  import { connectEscalatedFrame } from '@escalated-dev/escalated/embed';

  const frame = connectEscalatedFrame(document.getElementById('support-admin'), {
    origin: 'https://support.example.com',
    onNavigate: ({ route, title }) => highlightMenu(route),
  });
  frame.setTheme('light');
</script>
```

The frame sizes itself to its content and reports each page change; the
protocol is in the frontend guide.

### Session cookies in a frame

- **Same site** (`admin.example.com` framing `support.example.com`): Rails'
  default `SameSite=Lax` session cookie works.
- **Cross-site** (different registrable domains): the session cookie must be
  sent in a third-party context, so it needs `SameSite=None; Secure`:

  ```ruby
  # config/initializers/session_store.rb
  Rails.application.config.session_store :cookie_store, key: '_app_session', same_site: :none, secure: true
  ```

  and serve both sites over HTTPS (`config.force_ssl = true`). Browsers that
  block third-party cookies will still not keep a session in a cross-site
  frame; use the Vue + Inertia or server-rendered setup in that case.
- CSRF protection is unchanged.

## The admin menu: `escalated.navigation`

While embedding is on, every Inertia page shares the admin menu, and
`Escalated.admin_navigation(user, request = nil)` (in views,
`escalated_admin_navigation`) returns the same list, embedding on or off:

```json
[
  {
    "key": "tickets",
    "label": "Tickets",
    "route": "escalated.admin.tickets.index",
    "url": "/admin/support/tickets",
    "icon": "tickets",
    "position": 20,
    "active": true,
    "badge": null,
    "plugin": null,
    "children": []
  }
]
```

It is filtered for the user: empty for anyone who fails Escalated's admin gate
(`escalated_admin?`, unless you replaced it), screens whose feature is off are
left out (Roles while roles & permissions is off, API tokens while the API is
off, Plugins while plugins are off, Newsletters while they are off), and while
roles & permissions is on each item needs the permission its screen requires
(`Escalated::Support::RoutePermissions`). Plugin admin menu items
(`Escalated.plugin_ui.add_menu_item(section: 'admin', ...)` and SDK plugin
pages) are included, sorted by `position` with the core items; their `key` is
`plugin:<slug>:<n>` and `children` are their submenu items. Newsletters has no
frontend route name in this port, so its `route` is `null` and its `url` is
the standalone `/support/admin/newsletters`. Core `icon` keys match the
frontend's `escalatedNavIcons`.

## Security

- **The admin gate stays on by default.** Your `middleware` runs *in addition
  to* Escalated's admin gate (`require_admin!`, the user's `escalated_admin?`).
  Set `replace_admin_gate` only if your `middleware` itself restricts the
  routes to admins: with it on, your middleware is the only check on who
  reaches the admin. It is refused without `middleware`. Two-factor and route
  permissions still apply either way, and the agent panel and the pages that
  do not move keep Escalated's gates.
- **Guards fail closed.** A method name in `middleware` that the controller
  does not have raises rather than being skipped.
- **Framing is allow-listed.** In iframe mode only the origins you list (plus
  your own) may frame the admin; nothing else, and never `*`. Responses outside
  the embedded admin are not touched.
- **No open `postMessage`.** The frame talks only to an allow-listed parent
  origin and ignores messages from anywhere else.

## Turning it off

Remove the `embed_admin` call (or set `enabled: false` / `ESCALATED_EMBED=false`)
and restart. The admin returns to `/support/admin` with Escalated's own chrome,
the engine is mounted at `/support` again and `Escalated::EmbedFrameHeaders` is
no longer installed.
