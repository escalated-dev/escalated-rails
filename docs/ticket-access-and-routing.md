# Ticket access and routing

All options are independent and disabled by default. Install migration `063`
before enabling them; it adds nullable account columns and SLA targets.

```ruby
Escalated.configure do |config|
  config.visibility = 'department' # default: 'all'
  config.accounts = {
    enabled: true,
    scope_agents: true,
    resolver: ->(model) { model.respond_to?(:company) ? model.company : nil }
  }
  config.sla = config.sla.merge(targeted: true)
end
```

Department visibility restricts agents to their department memberships. Tickets
without a department are hidden. Assignment, ownership and following a ticket
provide no exception for an agent. Administrators keep access. Existing customer
and guest ownership checks continue to apply.

Package controllers automatically scope queries, including bearer-token API,
search, bulk actions, reports and widget lookups. Related replies, activities,
ratings, links, mentions, conversations and chat sessions follow ticket access.
Policies also check tickets loaded outside a request. Membership is read on
queries; contexts reset after each request.

Host services can wrap work in `Escalated::TicketAccess.with_actor(agent) { ... }`.
Background work without an actor retains full access. Trusted code can use
`Escalated::TicketAccess.with_actor(nil) { ... }` to bypass visibility while
retaining other model scopes. Raw SQL and host reverse joins must explicitly
apply the same access rules. Cloud-only mode rejects these local options.

The account resolver receives a requester, subject or agent and returns a
persisted Active Record model or nil. The package stores its polymorphic type
and string primary key, compared case-sensitively. Creation resolves the
requester; attaching a subject fills an empty account without replacing an
existing one. `TicketService.create` also accepts `subjects` so events see the
account. `ticket.account` resolves the host model; no company table is provided.
Account scope supports one account per agent. Nil grants no tickets. Account
and department restrictions intersect. Staff lists accept `account_type` and
`account_id` together; enabled account identities appear in staff/API responses.

Escalation conditions accept `ticket_type`, `account_type`, `account_id` and
`account: { type: 'Company', id: '123' }` (JSON string keys). Workflows and
automations accept the same fields in their existing condition format.
Compound workflow accounts support equals, not_equals, is_empty, is_not_empty.
Incomplete account identities fail closed.

SLA policies accept nullable `department_id` and `ticket_type`. Targeted
selection ranks both targets, department, type, then untargeted default;
lowest policy ID breaks ties. Without a match/default, no policy is selected.
With targeting off, existing department defaults and untargeted default policy
selection remain in effect. Department/type changes preserve the clock.
Explicitly call `Escalated::Services::SlaService.attach_policy(ticket)` to
reselect; targeted deadlines use the ticket creation time.

Automatic assignments, chat assignments and mail recipients are checked for
ticket access. Restricted agents cannot join broad AgentChannel streams;
they can use authorized TicketChannel/ChatChannel streams and scoped HTTP
polling. Ticket and chat streams recheck access before each delivery. Anonymous
chat subscriptions supply the private customer session identifier as `session`
when restrictions are enabled. Host integrations must not expose shared raw
broadcast streams directly to restricted agents.
