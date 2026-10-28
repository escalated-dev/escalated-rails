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
| Mobile API (when `api_enabled`) | `/<api_prefix>/mobile/guest` |

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

## Mobile guest API

The routes a mobile app uses to let a guest file a ticket, read it, reply to it
and get back into it. The canonical contract is
[mobile-guest-api](https://github.com/escalated-dev/escalated-developer-context/blob/main/domain-model/mobile-guest-api.md);
this section lists only what is specific to this port.

They are drawn with the REST API, so only while `config.api_enabled` is true
(default false), under `<api_prefix>/mobile` (default
`/support/api/v1/mobile`). Hosts that never enabled the API get no new routes.

| Method | Path | Guest budget |
| --- | --- | --- |
| POST | `/guest/verification` | tickets |
| POST | `/guest/lookup` | replies |
| POST | `/guest/tickets` | tickets |
| GET | `/guest/tickets/:token` | requests only |
| POST | `/guest/tickets/:token/replies` | replies |

- `verification` and `lookup` are the same handlers as on the guest pages and
  the widget. `:token` is the grant, the same one those surfaces issue: a grant
  from any of them opens the others.
- A bad, expired, rotated, revoked, malformed or chat grant is a 404. Legacy
  `guest_token` values are not accepted here.
- `POST tickets` takes JSON or `multipart/form-data` (`attachments[]`). It
  answers 403 while guest tickets are off, then 422 for field errors, then 422
  on `verification_code` for a bad proof, with nothing created. The contact,
  ticket (channel `web`), attachments, grant and spent code commit together;
  `ticket_created` fires afterwards. Status, assignee, metadata and external
  references cannot be set.
- `POST tickets/:token/replies` answers 404 for a bad grant, 422 on a closed
  ticket, 422 for field errors, and 403 when `email` (compared trimmed and
  lower-cased) is not the ticket's guest email. The reply is public, has no
  author and goes through `TicketService.reply`.
- Ticket answers are allow-listed: `metadata` is always `{}`, staff appear by
  display name only, and internal notes never appear. Attachment `url`s are the
  signed guest download links for the grant.

Rate limits, all per client IP:

- The API limiter (`api_rate_limit`, 60 a minute) covers every mobile route,
  with `X-RateLimit-Limit` and `X-RateLimit-Remaining`, and answers
  `429 { message: "Too many requests.", retry_after }`.
- `guest_rate_limit`: `requests_per_minute` (60) on every mobile guest route,
  plus the `tickets_per_minute` (5) and `replies_per_minute` (10) budgets the
  guest pages and widget share. Over a budget: 429 with `Retry-After`.

Every answer, errors and 429s included, carries `Cache-Control: private,
no-store` and `Referrer-Policy: no-referrer`. Keep the `:token` path segment
out of access logs.

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
- The mobile guest routes' attachment limit is 10 or `max_attachments`
  (default 5), whichever is lower.
- The `requests_per_minute` budget is counted on the mobile guest routes only;
  the guest pages and widget keep their ticket and reply budgets.
- Lookup matches the ticket `reference` only.
