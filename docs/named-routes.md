# Named routes

The components in `@escalated-dev/escalated` build every URL with Laravel's
Ziggy-style helper, `route(name, params)`: `route('escalated.admin.tickets.show', ticket.reference)`.
Laravel hosts get that helper from Ziggy. This engine ships its own list and a
small compatible helper, so a Rails host does not map names by hand.

## What the engine provides

- `Escalated::RouteList.routes`: every name the frontend calls that this engine
  serves, mapped to its real path and methods, under `config.route_prefix`.
- A `ziggy` prop on every Escalated Inertia response (staff, customer and guest
  screens), in the shape ziggy-js reads:

  ```json
  {
    "url": "https://example.com",
    "port": null,
    "defaults": {},
    "routes": {
      "escalated.admin.tickets.show": { "uri": "support/admin/tickets/{id}", "methods": ["GET", "HEAD"] }
    },
    "location": "https://example.com/support/admin/tickets"
  }
  ```

  Placeholders use the engine's parameter names (`{id}`, `{reply_id}`,
  `{token}`, ...). The components pass values positionally, so the names only
  matter to keyed calls such as `route('escalated.admin.reports.agent-detail', { id })`.

- `escalated_route_helper_tag`, a view helper that renders the `route()` helper
  as an inline script (with the request's CSP nonce when the host issues one).

## Installing the helper

The host owns the Inertia layout. Put the tag before the script that mounts the
app, because the frontend's plugin installs a stub that throws when no
`window.route` exists by the time it loads:

```erb
<head>
  <%= csrf_meta_tags %>
  <%= escalated_route_helper_tag %>
  <%= vite_javascript_tag 'application' %>
</head>
```

The helper reads the page's `ziggy` prop the first time it is called, so the
tag may sit in `<head>`, ahead of the Inertia root element.

## Overriding

The host wins, at three levels:

1. **A `window.route` your app installs** (ziggy-js, or a shim of your own) is
   left alone: the helper only installs itself when `window.route` is not
   already a function.
2. **`window.Ziggy.routes`**, when set, is read before the `ziggy` prop.
3. **`config.route_overrides`** replaces or adds single names on the server,
   so the prop already carries them:

   ```ruby
   Escalated.configure do |config|
     config.route_overrides = {
       'login' => '/users/sign_in',                                   # GET
       'escalated.customer.kb.index' => { uri: '/help', methods: %w[GET HEAD] }
     }
   end
   ```

## Names that are not in the list

An unknown name logs `[escalated] no route named ...` to the console and
returns `#`. These names the frontend calls have no working endpoint here:

- `login`: the host owns sign-in, and the engine has no login path to point
  at. Map it with `config.route_overrides`.
- `escalated.agent.tickets.snooze` / `unsnooze`: only admins can snooze.
- `escalated.admin.tickets.links.*`, `escalated.admin.tickets.merge`,
  `escalated.admin.tickets.merge-search`,
  `escalated.admin.tickets.side-conversations.*`: the routes exist but their
  controllers do not work against this engine's models yet.
- `escalated.admin.workflows.logs`: there is no all-workflows run log.

`spec/lib/escalated/route_list_spec.rb` keeps this honest: every name in
`spec/fixtures/frontend-route-names.txt` (regenerated from the frontend, see the
file's header) must be in the list or in that spec's allowlist, and every listed
path is checked against the engine's router.
