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
| Two-factor authentication | `config.access = { two_factor: true }` | `ESCALATED_TWO_FACTOR` |
| Single sign-on | `config.access = { sso: true }` | `ESCALATED_SSO` |

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

### Giving users roles from Admin > Users

While the switch is on, **Admin > Users** shows each user's roles and an admin
with `role.manage` can tick and untick them. The screen saves with
`PUT /support/admin/users/:user_id/roles` and `{ "role_ids": [...] }`, which
replaces the user's roles with exactly that set, as escalated-laravel. The ids
must be existing roles (422 otherwise), and you cannot take away your own
`role.manage` ("You cannot remove your own role management."). While the switch
is off the route answers 404 and the screen shows no roles.

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

## Two-factor authentication

### What is enforced

With `ESCALATED_TWO_FACTOR=true` (and the `068` migration run):

- TOTP is RFC 6238 (SHA-1, 6 digits, 30 s) through the `rotp` gem, with one
  step of drift either side. A code's time step is recorded when it is
  accepted, and that step or an earlier one is refused afterwards.
- A staff user with a confirmed enrolment who opens any admin or agent page
  without having passed the challenge in this session is redirected to
  `GET /support/two-factor/challenge` (`Escalated/Auth/TwoFactorChallenge`,
  props `action` and `error`). JSON requests get
  `403 {"two_factor_required": true}`.
- The challenge posts `code` or `recovery_code` to
  `POST /support/two-factor/challenge`. Success renews the session (keeping its
  data), marks it for that user and returns to the page they asked for.
  Failure is a validation error on the field sent. Five attempts per user per
  minute (`config.two_factor[:cache_store]`, default `Rails.cache`); then 429.
- Eight single-use recovery codes are issued at setup; a code that signs
  someone in is removed. Secrets and recovery codes are sealed at rest with a
  key derived from `secret_key_base`; enrolments stored before are read as
  they are.
- Enrolment (`/support/admin/settings/two_factor`, and `setup`, `confirm`,
  `disable`) is open to every staff user, not only admins, and needs no
  permission. Confirming marks the session as passed.
- The token API is not session-based and is not challenged.
- Every login is challenged again: with Warden (Devise) the mark is cleared on
  sign-in and sign-out. Hosts on other authentication call
  `Escalated::Support::TwoFactorSession.forget(session)` when someone signs in
  or out.

### Requiring it

`config.two_factor = { required: true }` (`ESCALATED_TWO_FACTOR_REQUIRED`), or
the `two_factor_required` setting (posted to `/support/admin/settings`, which
now saves only the keys a form sends; the setting wins once saved). When
required, a staff user without an enrolment is sent to enrol and can use
nothing else until they do. Pages get `escalated.two_factor_required`.

### Lost device

`rake "escalated:two_factor:reset[user@example.com]"` removes a user's
enrolment.

### While it is off

The enrolment and challenge routes answer 404 and nobody is challenged.
Enrolments are kept.

## Single sign-on

### Turning it on

1. Run the migrations (`069` creates `escalated_sso_message_ids`).
2. Choose the provider in **Admin > Settings > SSO** and give the identity
   provider the endpoints that page lists.
3. Decide how users are signed in: Devise's `sign_in` is used when the
   controller has it, else `config.sso[:sign_in]` (a callable taking the
   controller and the user).
4. Set `config.access = { sso: true }` or `ESCALATED_SSO=true`.

| `config.sso` key | Env var | Default |
|---|---|---|
| `sp_entity_id` | `ESCALATED_SSO_SP_ENTITY_ID` | the SP metadata URL |
| `allow_idp_initiated` | `ESCALATED_SSO_ALLOW_IDP_INITIATED` | false |
| `jwt_audience` | `ESCALATED_SSO_JWT_AUDIENCE` | the app's root URL |
| `clock_skew` | `ESCALATED_SSO_CLOCK_SKEW` | 120 (max 300) |
| `create_users` | `ESCALATED_SSO_CREATE_USERS` | false |
| `sync_roles` | `ESCALATED_SSO_SYNC_ROLES` | false |
| `redirect_to` | `ESCALATED_SSO_REDIRECT_TO` | the agent dashboard |
| `sign_in` | | Devise `sign_in` |

### Routes

| Route | Use |
|---|---|
| `GET /support/sso/login` | Start sign-in with the configured provider (404 while it is `none`) |
| `GET /support/sso/saml/metadata` | SP metadata; its URL is the default SP entity ID |
| `POST /support/sso/saml/acs` | SAML assertion consumer (HTTP-POST binding) |
| `GET /support/sso/oauth/callback` | OAuth 2 / OIDC redirect URI |
| `GET\|POST /support/sso/jwt/callback` | JWT hand-off (`jwt` parameter) |

Every route answers 404 while SSO is off or serves a provider other than the
chosen one. Every refusal answers a generic 403 and logs the reason.

### What is checked

- **SAML** (`ruby-saml`, strict): the IdP certificate must be configured; the
  assertion must be signed by it (a signed Response alone is not enough);
  `EncryptedAssertion` is refused; Issuer, Audience (the SP entity ID),
  Destination and the bearer Recipient (the ACS URL) and the validity windows
  are checked; `InResponseTo` must name an AuthnRequest issued in the last 10
  minutes, stored in the database and consumed on use (unsolicited responses
  only with `allow_idp_initiated`); the assertion ID is used once.
- **OAuth 2 / OIDC** (`oauth2`): authorization code with a single-use `state`
  kept in the session and PKCE (`S256`); the code is exchanged server to server
  and the profile read from the userinfo URL. A missing or mismatched `state`,
  an IdP `error`, or `email_verified: false` is refused.
- **JWT** (`jwt`): the algorithm is pinned to the configured one (so `none` and
  algorithm switching are refused), `exp` and `jti` are required, `aud` must
  name this install, and a `jti` is used once.

### Users and roles

The email comes from the configured attribute or claim (SAML falls back to an
email-shaped NameID) and is matched to a host user case-insensitively. An
unknown email is refused unless `create_users` is on, which creates a user with
that email, name and a random password. With roles & permissions on and
`sync_roles`, an asserted role naming an existing Escalated role slug replaces
the user's roles; an unknown one changes nothing. SSO never grants the host's
admin or agent gate. A successful sign-in renews the session and clears the
two-factor mark, so SSO does not skip the challenge.
