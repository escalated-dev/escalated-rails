# Private attachments

Attachment links point to the engine's download route,
`GET /<route_prefix>/attachments/:id?token=...`, and never to storage.
The engine no longer hands out `rails_blob_path` links or presigned service
URLs.

## The token

The token is signed with the host's `secret_key_base` and names one
attachment. It expires after `attachment_download_ttl_minutes`: the default is
10, and it can be set from 1 to 60. Refresh the page to get a fresh link.

## Who can download

A valid token is not enough on its own. The request must also pass the access
check at download time, as one of these:

- **Agents and admins** who can see the ticket under the configured visibility
  (`TicketPolicy#show?`). This includes internal-note attachments.
- **The requester**, for files on the ticket and on public replies. Never for
  internal-note files.
- **Guests.** The guest ticket page puts a capability in each link. It is bound
  to that ticket and to the ticket's guest credential, so changing the
  credential revokes every link issued under it. It never covers internal
  notes.

## How the session is read

- Browser downloads use the host session. The route skips
  `configuration.middleware`, so a guest is not sent to the host's sign-in
  page.
- API clients send their `Authorization: Bearer` token. A bad bearer token gets
  a 401. It never falls back to the session.

## The response

- `Content-Disposition: attachment` with the stored name, after removing any
  path and control characters
- `X-Content-Type-Options: nosniff`
- `Cache-Control: private, no-store`
- `Referrer-Policy: no-referrer`
- The stored type for PNG, JPEG, GIF, WebP and PDF. Everything else, SVG and
  HTML included, is sent as `application/octet-stream`.

## Upgrading

- Links handed out before this release were ActiveStorage redirect URLs. Their
  signed blob ids do not expire.
- If the host does not use ActiveStorage's own routes for anything else, set
  `config.active_storage.draw_routes = false`. Every old link then stops
  working.
- Otherwise, treat any old link that was shared outside the help desk as still
  live.
- With a cloud service (S3, GCS, Azure), keep the bucket private (no `public:
  true` in `storage.yml`). The engine now streams files itself.
