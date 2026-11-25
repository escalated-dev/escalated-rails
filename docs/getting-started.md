# Getting started

## Requirements

- Ruby 3.1+
- Rails 7.1+
- Node.js 18+ (for frontend assets)

## Quick Start

```bash
bundle add escalated
npm install @escalated-dev/escalated
rails generate escalated:install
rails db:migrate
```

`rails generate escalated:install` adds three methods to `app/models/user.rb`. They are how
Escalated tells staff from customers; edit them to match your own roles:

```ruby
class User < ApplicationRecord
  def escalated_agent?     # support agents (return true for admins as well)
    %w[agent admin].include?(role)
  end

  def escalated_admin?     # support admins
    role == "admin"
  end

  def self.escalated_agents # every agent, for assignee lists
    where(role: %w[agent admin])
  end
end
```

If your User model has none of them, signing in to the agent or admin screens raises
`Escalated::UserModelNotConfigured`, which names the missing methods. Check the setup at any time
with:

```bash
bin/rails escalated:doctor
```

### Required: schedule the recurring jobs

SLA checks, escalation rules, automations and snooze wake-ups only run when your app schedules
`Escalated::CheckSlaJob`, `Escalated::EvaluateEscalationsJob`, `Escalated::RunAutomationsJob` and
`Escalated::WakeSnoozedTicketsJob` (plus the daily and weekly housekeeping jobs). The intervals and
a Solid Queue / `whenever` recipe are in [docs/operations.md](operations.md#required-schedule-the-recurring-jobs).
Until the SLA check runs, the admin Settings and Reports pages warn that the jobs are not
running.

Visit `/support` — you're live.

## Embedding the admin in your own admin panel (optional)

Escalated's admin is a standalone panel at `/support/admin`, and that stays the default: nothing below changes anything until you turn it on. If your app already has an admin panel, you can mount Escalated's admin screens under your prefix and guards instead, render them inside your Inertia/Vue layout or your ERB admin layout (or an allow-listed iframe), and list Escalated's admin menu in your own sidebar:

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

Route names stay the same, so links follow the move; Escalated's admin gate, two-factor and route permissions stay on. The agent panel, customer portal, widget, API, SSO, two-factor and newsletter URLs do not move. Setup for each kind of host, the `ESCALATED_EMBED*` env vars and the security notes are in [docs/embedding-admin.md](embedding-admin.md).

## Ticket subjects

A ticket has a **requester** (who raised it) and a **subject line** (free text). You can also attach host-app entities the ticket is *about* — a Project, Customer, asset, and so on — so agents see context and can jump into your app.

Include `Escalated::PresentsAsTicketSubject` on any attachable model and override presentation methods as needed:

```ruby
class Project < ApplicationRecord
  include Escalated::PresentsAsTicketSubject

  def ticket_subject_subtitle
    "Project · #{customer.name}"
  end

  def ticket_subject_url
    project_path(self)
  end

  def ticket_subject_color
    '#2563eb'
  end

  def ticket_subject_icon
    'folder'
  end
end
```

Attach, detach, or sync subjects on a ticket (several allowed):

```ruby
ticket.attach_subject(project, role: 'project')
ticket.attach_subject(customer, role: 'account')
ticket.sync_subjects([[project, 'primary'], customer])
ticket.detach_subject(project)
```

Each subject is serialized on the ticket as `{ type, id, role, title, subtitle, url, color, icon, missing }`. `subject_id` is stored as a string so integer, UUID, and string host keys all work.

Allow agent/admin attach endpoints by listing permitted models in configuration (empty list disables the API; programmatic attach still works when empty):

```ruby
Escalated.configure do |config|
  config.ticket_subject_types = [
    'Project',
    'Customer',
    # morph alias => class
    # 'project' => 'Project',
  ]
end
```

Endpoints: `POST /support/agent/tickets/:id/subjects` and `DELETE .../subjects/:subject_id` (admin routes mirror under `/support/admin/`). Pass `type`, `subject_id`, and optional `role` in the body, or nest them under `subject` (useful when you need Laravel-style `id` without colliding with the ticket route param).
