# Verified guest access

Guests must prove they can read the mailbox before they can do any of these:

- create a ticket, from the guest form or the widget
- start a live chat
- look up a ticket

This follows escalated-laravel's `docs/guest-access.md`. The shared frontend
(`@escalated-dev/escalated` 0.12.3 and later) already sends the code step. It
asks for a code whenever Guest/Create receives `verification_url` or the
widget's `/config` says `guest_verification_required: true`.

## Before you deploy

- Run the migration. `065_add_verified_guest_access` adds four nullable ticket
  columns and the `guest_verifications` table. It works on SQLite, PostgreSQL
  and MySQL.
- Configure outbound mail. Codes are sent with `deliver_now` from
  `Escalated::GuestMailer`.
- Use a shared `Rails.cache`, such as Redis or Memcached, across all
  processes. The code budgets are counted there.
- Keep `secret_key_base` the same on every process. It keys the code digests
  and encrypts the grants.

## Email codes

Each prefix has `POST verification` and `POST lookup`:

| Surface | Prefix |
| --- | --- |
| Guest pages | `/support/guest` |
| Widget | `/support/widget` |

### Requesting a code

Send `{ "email": "...", "purpose": "ticket" | "chat" | "lookup" }`.

- The answer is `202 { verification_id, expires_in: 600, message }`.
- The 8-digit code is only ever in the email.
- `ticket` and `lookup` need guest tickets to be on. `chat` needs `chat_enabled`.

### Using a code

Send the `verification_id` and `verification_code` with the request it was
asked for. A proof:

- is bound to the normalised email and the purpose
- expires after 10 minutes
- allows 5 guesses
- can be used once

The check and the ticket write commit in one transaction. Wrong guesses still
count, and an operation that fails hands the proof back so it can be retried.
For chat, the proof is used just before the chat starts.

### Code budgets

The codes sent to one mailbox are limited per hour:

| Budget | Default | Setting |
| --- | --- | --- |
| From one client IP | 3 | `guest_codes_per_client_per_hour` |
| From all clients together | 10 | `guest_codes_per_mailbox_per_hour` |

Over either budget, the answer is a 429 with `Retry-After`. The per-IP guest
throttles (`guest_rate_limit`) apply as well. `verification` counts as a
submission and `lookup` as a reply.

## Grants

A new guest or widget ticket gets an expiring grant instead of a permanent
`guest_token`:

- **Guest form:** redirects to `/support/guest/<grant>`.
- **Widget:** answers with `guest_access_token` and `expires_at`.

A grant is an encrypted, authenticated token, and clients should treat it as
opaque. Grants last `guest_access_ttl_minutes`: the default is 1440, and it
can be set from 5 minutes to 7 days.

The ticket stores only a SHA-256 of the grant's nonce. Any of these
invalidates every earlier grant, and the attachment links issued under them:

- issuing a new grant
- changing the ticket's `guest_email`
- calling `Escalated::GuestAccess.revoke(ticket)`

### Where grants are used

- **The guest page, reply and rating routes** take the grant where the token
  used to go.
- **The widget status view** sends `GET /widget/tickets/:reference` with
  `Authorization: Bearer <grant>`. An email query parameter never authorises
  it.
- **Guest page and widget responses** are sent with `Cache-Control: no-store`
  and `Referrer-Policy: no-referrer`. Keep grant path segments and
  `Authorization` headers out of access logs.

### Lookup

`POST lookup` takes `email`, `reference`, `verification_id` and
`verification_code`. It answers `{ data: [{ reference, subject,
guest_access_token, expires_at }] }`.

- It returns up to 20 of the guest's tickets with that reference whose guest
  email is the verified one.
- A reference alone finds nothing.
- An empty result still uses up the code.
- Lookup works for older tickets too, including guest tickets from inbound
  email. It issues each one a grant, which retires that ticket's permanent
  token.

## Tickets created before this release

Their permanent `guest_token` links keep working while
`accept_legacy_guest_tokens` is on, which is the default in this release. This
applies on the guest page, and on `GET /widget/tickets/:token` without a
bearer token. A token stops working once:

- a grant is issued for its ticket, through lookup
- the ticket's guest email changes
- `accept_legacy_guest_tokens` is set to `false`

The plan is to turn it off by default in a later minor release. Guests holding
an old link can then verify their email in the lookup form to get a new one.
Hosts that want to retire old links now can set
`config.accept_legacy_guest_tokens = false`.

## Differences from Laravel

- Laravel stops honouring legacy tokens at once. Here they keep working until
  the switch above is turned off.
- Live chat needs a chat-purpose proof. The chat token is a random token
  stored as its SHA-256 that expires `guest_access_ttl_minutes` after the chat
  starts, like Laravel's chat grant; it is not a sealed grant, so it does not
  share the ticket's `guest_access_hash` and is not rotated by a ticket link.
- There is no mobile guest API in this port, so there is no mobile prefix.
