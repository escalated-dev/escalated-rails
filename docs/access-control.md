# Access control: roles & permissions, two-factor, SSO

Escalated's roles & permissions, two-factor authentication and single sign-on
are **install-level switches**, off by default
([ADR 2026-10-29](https://github.com/escalated-dev/escalated-developer-context/blob/main/decisions/2026-10-29-configurable-access-features.md)).
While a switch is off its screens and routes answer 404 and nothing is
enforced; the host's `escalated_admin?` / `escalated_agent?` gates decide who
may do what, exactly as before. While it is on, the feature is enforced.

The switches are read from configuration, else the environment. No admin
screen or stored setting changes them.

| Feature | Config | Env var |
|---|---|---|
| Roles & permissions | `config.access = { roles_permissions: true }` | `ESCALATED_ROLES_PERMISSIONS` |

```ruby
Escalated.configure do |config|
  config.access = { roles_permissions: true }
end
```

## Roles & permissions

### What is enforced

With the switch on, every admin, agent and staff API action needs a permission
**in addition to** the host gate for that area. A user's permissions are the
union of their Escalated roles' permissions (`escalated_role_users`). Nothing
else grants one: passing the admin gate or `is_admin` gives no permissions by
itself. Give users who should have everything the `admin` role.

- The action to permission map is `lib/escalated/support/route_permissions.rb`
  (escalated-laravel's `RoutePermissions`, keyed by `controller#action`). An
  action missing from it is refused, and a spec walks every route so a new one
  cannot ship unmapped.
- A status change needs `ticket.edit`, plus `ticket.close` when the new status
  is `resolved`, `closed` or `reopened`.
- Bulk actions need the permission of the action: `assign` needs
  `ticket.assign`, `delete` needs `ticket.delete`, `close` needs `ticket.close`,
  the rest `ticket.edit`.
- Applying a macro needs `macro.view` and `ticket.edit`; an internal API reply
  needs `reply.create_internal`.
- API tokens act as their owner, so the staff API checks the owner's
  permissions as well as the token's abilities.
- The newsletter screens check `newsletters.manage` and `newsletters.send`, and
  plugin menu items, widgets and slots check their `permission`, only while the
  switch is on.
- Your own two-factor screens need no permission.

Failing a permission answers 403.

### Seeded roles

`rake escalated:permissions:seed` (or `db/seeds/permissions.rb`) creates the
permissions and three system roles:

| Role | Permissions |
|---|---|
| `admin` | all |
| `agent` | `ticket.*`, `reply.*`, `kb.view`, `report.view`, `macro.view`, `macro.create`, `tag.view`, `custom_field.view`, `audit.view` |
| `light_agent` | `ticket.view`, `reply.create`, `reply.create_internal`, `kb.view`, `macro.view`, `tag.view` |

Custom roles are made in **Admin > Roles**, which exists while the switch is on.

### Turning it on

1. `rake escalated:permissions:seed`
2. Give every staff user a role, starting with yourself:
   `rake "escalated:roles:assign[you@example.com,admin]"` (email or id).
3. Set `config.access = { roles_permissions: true }` or
   `ESCALATED_ROLES_PERMISSIONS=true`.

Staff without a role can still reach their personal screens and nothing else.

### Shared props

Every page gets `escalated.features.roles_permissions` (boolean) and
`escalated.permissions`: the user's slugs while on, `['*']` for staff while
off, `[]` for everyone else.
