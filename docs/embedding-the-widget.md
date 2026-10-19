# Embedding the widget on other sites

The support widget, ticket form and live chat can run on a site other than
the one Escalated is installed on: a store, a marketing site or a customer
portal loads one script from your Escalated install. Nothing changes until you
list the sites that may do this.

## 1. Allow the embedding sites

Either in the host app's configuration (by default read from the environment):

```ruby
# config/initializers/escalated.rb
Escalated.configure do |config|
  # Defaults to ENV['ESCALATED_WIDGET_ALLOWED_ORIGINS'], comma separated.
  config.widget_allowed_origins = ['https://shop.example.com', 'https://*.example.org']
end
```

```sh
ESCALATED_WIDGET_ALLOWED_ORIGINS=https://shop.example.com,https://*.example.org
```

or in the admin settings as `widget_allowed_origins` (one per line). Both
lists are combined. Each entry is an origin: `scheme://host[:port]`, http or
https, no path, query or user info. `https://*.example.org` matches every
subdomain of `example.org` but not `example.org` itself. A bare `*` is
rejected, and the admin settings refuse any entry that is not an origin.

Turn the widget on in the same settings screen (`widget_enabled`).

## 2. Add the script to the other site

```html
<script src="https://help.example.com/support/widget/embed.js" async></script>
```

For an on-page support form instead of a floating button:

```html
<div id="support-form"></div>
<script
    src="https://help.example.com/support/widget/embed.js"
    data-mode="inline"
    data-target="#support-form"
    data-tabs="ticket"
    data-meta-order-number="A-1001"
></script>
```

All host parameters (tabs, department, prefill, metadata, title, the
JavaScript API) are described in the frontend package
[`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated).

## What the server does

For a request whose `Origin` is on the list, every route under
`{route_prefix}/widget` (chat included):

- answers preflight requests (`OPTIONS` with `Access-Control-Request-Method`)
  with 204 and the allowed methods and headers, cached for
  `widget_preflight_max_age` seconds (600);
- adds `Access-Control-Allow-Origin: <origin>`, `Vary: Origin` and
  `Access-Control-Expose-Headers: Retry-After` to every response, including
  403, 404, 422 and rate-limit (429) answers. `Access-Control-Allow-Credentials`
  is never sent;
- treats the visitor as a guest even if the same browser is signed in to the
  host app: `current_user` is `nil` for these requests.

Requests from any other origin, and same-origin requests, are handled exactly
as before. The widget endpoints already used `protect_from_forgery with:
:null_session`, so a POST without a CSRF token was never refused there and that
is unchanged. Rate limits and the `widget_enabled` switch apply to embedded
requests unchanged.

Rails' own CORS middleware (`rack-cors`) is not needed for these routes. If
the host app adds `rack-cors` rules for `/support/widget/*`, those rules answer
the preflight first.

### Host parameters

`GET /widget/config` returns `accepts_metadata: true`. Widget tickets and live
chats accept an optional `metadata` object. It is merged into the ticket's
`metadata` (the server's `source` key wins); live chats also store it on the
chat session's `metadata`, next to the server-recorded `user_agent` and `ip`
on the ticket.

The values come from the visitor's browser, so only a flat map is kept: up to
25 entries, keys of letters, digits, `_ . : -` (64 characters at most), and
string, number or boolean values (strings trimmed and cut to 500 characters).
`page_url` is kept only when it is an http(s) URL of at most 2048 characters.
`embedded_on` is always set by the server from the request's allowed `Origin`
and cannot be supplied by the page. `metadata` that is not an object, or has
more than 50 keys, is refused with 422. Treat all of it as unverified visitor
input.

### The script

`GET {route_prefix}/widget/embed.js` serves `vendor/widget/escalated-widget.js`
from the gem, built from `@escalated-dev/escalated`, with a one-hour public
cache, an ETag (304 on `If-None-Match`), `Cross-Origin-Resource-Policy:
cross-origin` and `Access-Control-Allow-Origin: *`. Set
`config.widget_serve_script = false` to unmount the route, for example when
you serve the bundle from a CDN. Pages then need `data-base-url`.

## Configuration

```ruby
Escalated.configure do |config|
  config.widget_allowed_origins = [...] # default: ESCALATED_WIDGET_ALLOWED_ORIGINS, comma separated
  config.widget_preflight_max_age = 600 # seconds browsers may cache a preflight
  config.widget_serve_script = true     # mount {route_prefix}/widget/embed.js
end
```

## Troubleshooting

- **The browser reports a CORS error.** The page's origin is not on the list,
  or it differs in scheme or port (`http://` vs `https://`, `:8080`).
- **A signed-in agent sees guest behaviour in the embed.** Intended: requests
  from another site never use the host session.
