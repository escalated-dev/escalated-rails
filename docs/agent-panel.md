# Agent panel data

What this engine sends the shared frontend's agent panel beyond the ticket
pages' required props. The contract is ADR
[2026-11-05-agent-panel-data](https://github.com/escalated-dev/escalated-developer-context/blob/main/decisions/2026-11-05-agent-panel-data.md)
in escalated-developer-context; escalated-laravel is the reference
implementation. Everything here is optional: an older frontend ignores it.

Run `bin/rails escalated:install:migrations db:migrate` for migration
`070_create_escalated_agent_panel_data`.

## The agent's own status

| Route | Name | Body | Answer |
|---|---|---|---|
| `PUT`, `PATCH` or `POST /{prefix}/agent/status` | `escalated.agent.status` | `{ "status": "online" \| "away" \| "offline" }` | `{ "agent_status": "away" }` (JSON); back (Inertia visit); 422 for any other value |

The status is `agent_profiles.chat_status`, the field live-chat routing reads.
The admin route `POST /{prefix}/admin/chat/update_status` still writes it and
now also answers `agent_status`. Agents share `escalated.agent_status`
(`offline` until set) and `escalated.agent_statuses`. No event is emitted.

## Knowledge-base search

`GET /{prefix}/agent/kb/search?q=` (`escalated.agent.kb.search`, `kb.view`
under roles & permissions): `q` 2 to 200 characters, `limit` 1 to 20 (default
10), otherwise 422. Answers `{ data: [{ id, title, excerpt, url, category, updated_at }] }`
for published articles, where `url` is the absolute customer knowledge-base
URL. Case-insensitive `LIKE` on title and body with `%` and `_` literal, title
matches first, then the most recently updated. 404 while the knowledge base is
off. `Escalated::Article.search` (customer and widget searches) escapes the
same way now.

## Unread tickets

- `tickets.last_customer_activity_at` is set when a ticket is created (not
  while importing) and on public replies from the requester, a contact, a
  guest (no author) or a host user who is not staff. Agents' replies, notes,
  system messages and a workflow's canned reply never move it.
- `escalated_ticket_reads` (`user_id`, `ticket_id`, `last_read_at`); a null
  `last_read_at` means marked unread. Rows go with the ticket.
- Opening `escalated.agent.tickets.show` marks the ticket read.
- `POST /{prefix}/agent/tickets/{id}/read` and `/unread`
  (`escalated.agent.tickets.read` / `.unread`, `ticket.view`) answer
  `{ is_unread }` or go back; the agent and admin bulk routes take
  `mark_read` and `mark_unread`.
- `is_unread` on TicketIndex rows and the TicketShow ticket; `inbox.unread`
  (`{ mine, unassigned, all }`). Neither is sent in cloud mode.

## Customer online status

`requester_online` and `requester_last_seen_at` on TicketIndex rows and the
TicketShow ticket, from one query per page, never on customer, guest or widget
responses. The customer is the requester, else the ticket's contact, else the
ticket itself. Last-seen (`escalated_customer_presence`) is recorded by the
customer ticket pages (staff skipped), the widget chat (start, messages,
typing, end, rate) and the widget ticket lookup, at most once per customer
every 30 seconds by a conditional `UPDATE`. Online means within
`config.presence_online_window_seconds` (`ESCALATED_PRESENCE_ONLINE_WINDOW`,
default 120).

## Notifications

`escalated_notifications` holds the agents' in-app notifications;
`config.agent_notifications = false` turns the feed off (routes 404, no
shared prop).

| `type` | Sent to | When |
|---|---|---|
| `ticket_assigned` | the assignee | someone else assigns them a ticket (self-assignment sends nothing, email included) |
| `ticket_reply` | the assignee and followers | a customer-side public reply |
| `mention` | the mentioned agent | an @mention in an internal note |
| `sla_warning` / `sla_breached` | the assignee | `sla_warning` / `sla_breached` |
| `chat_transferred` | the receiving agent | a chat is transferred to them by someone else |

| Route | Name | Answer |
|---|---|---|
| `GET /{prefix}/agent/notifications` | `escalated.agent.notifications.index` | `{ data, meta: { current_page, last_page, per_page, total }, unread_count }`; `?page`, `?per_page` (20, max 50), `?unread=1` |
| `POST /{prefix}/agent/notifications/{id}/read` | `escalated.agent.notifications.read` | `{ unread_count }`; 404 for someone else's |
| `POST /{prefix}/agent/notifications/read-all` | `escalated.agent.notifications.read-all` | `{ unread_count: 0 }` |

Items are `{ id, type, title, body, ticket, url, created_at, read_at }`;
titles are translated (`escalated.agent_notifications.*`, all 14 locales). A
ticket the agent can no longer see is redacted (`ticket`, `url`, `body` null,
generic title). Agents share `escalated.notifications.unread_count`. While
broadcasting is on, each new item goes to ActionCable channel
`escalated_agent_{id}` as event `notification.created`. Mute preferences are
not built.
