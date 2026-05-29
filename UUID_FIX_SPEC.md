# Task: support UUID/string host-app user keys (escalated-rails)

The Rails engine assumes the HOST app's user primary key is a `bigint`. Hosts
whose `users.id` is a UUID/string break: migrations create `bigint` FK columns
that can't hold a UUID, and several controllers/services call `.to_i` on user
ids (turning a UUID into `0`). Make the engine work with integer **and**
UUID/string host user keys, **defaulting to the current bigint behavior** so
existing installs are unaffected.

## Step 1 — Config + resolver helper

In `lib/escalated/configuration.rb` add an accessor `user_id_type` defaulting to
`:auto`. (Find the existing `attr_accessor` list / `initialize`; add it there,
keep `user_class` as-is.)

Add a module helper (in `lib/escalated.rb` or a small new
`lib/escalated/user_key.rb` required from `lib/escalated.rb`):

```ruby
module Escalated
  # Returns the ActiveRecord column type to use for host-user foreign keys:
  # :bigint (default) | :uuid | :string. With :auto it introspects the
  # configured user model's primary key type, falling back to :bigint.
  def self.user_id_type
    configured = configuration.user_id_type
    return configured unless configured.nil? || configured == :auto

    klass = configuration.user_class.to_s.safe_constantize
    if klass&.table_exists?
      col = klass.columns_hash[klass.primary_key.to_s]
      case col&.type
      when :uuid then :uuid
      when :string, :text then :string
      else :bigint
      end
    else
      :bigint
    end
  rescue StandardError
    :bigint
  end
end
```

## Step 2 — Migrations (the schema fix)

In EVERY migration file listed below, replace the hardcoded host-user-id column
declaration with one of the configured type. Use this form:

```ruby
t.column :assigned_to, Escalated.user_id_type
# was: t.bigint :assigned_to
```

For polymorphic user refs that currently do `t.bigint :requester_id` +
`t.string :requester_type` (or `t.references ... polymorphic`), keep the
`_type` string column and only switch the `_id` column to
`t.column :requester_id, Escalated.user_id_type`.

ONLY change columns that store a **host user id**. Do NOT touch Escalated's own
integer PKs/FKs (ticket_id, department_id, role_id, skill_id, etc.).

Files + columns (from audit — verify exact lines):
- `db/migrate/004_create_escalated_tickets.rb` — `requester_id` (polymorphic _id), `assigned_to`
- `db/migrate/005_create_escalated_replies.rb` — `author_id` (polymorphic _id)
- `db/migrate/008_create_escalated_support_tables.rb` — `created_by`
- `db/migrate/009_create_escalated_ticket_activities.rb` — `causer_id` (polymorphic _id)
- `db/migrate/013_create_escalated_macros.rb` — `created_by`
- `db/migrate/014_create_escalated_ticket_followers.rb` — `user_id`
- `db/migrate/019_create_escalated_audit_logs.rb` — `user_id`
- `db/migrate/022_create_escalated_roles_and_permissions.rb` — `user_id` (role_users join)
- `db/migrate/026_create_escalated_side_conversations.rb` — `created_by_id`, `author_id`
- `db/migrate/027_create_escalated_knowledge_base.rb` — `author_id`
- `db/migrate/028_create_escalated_agent_tables.rb` — `user_id` (×3: agent profiles/skills/capacity)
- `db/migrate/031_create_escalated_two_factor.rb` — `user_id`
- `db/migrate/035_create_escalated_saved_views.rb` — `user_id`
- `db/migrate/040_add_snooze_fields_to_escalated_tickets.rb` — `snoozed_by`
- `db/migrate/044_create_escalated_mentions.rb` — `user_id`
- `db/migrate/045_create_escalated_contacts.rb` — `user_id`

(If `Escalated.user_id_type` isn't loadable inside a migration, require the
engine at the top or reference `::Escalated.user_id_type` — make sure migrations
still run.)

## Step 3 — Remove `.to_i` casts on host user ids

Remove the integer coercion (pass the raw value through) at these sites:
- `app/controllers/escalated/admin/settings_controller.rb` lines ~110, ~126 — `guest_policy_user_id` (store/read the raw value, don't `.to_i`).
- `app/controllers/escalated/guest/tickets_controller.rb` ~81 — `guest_user_id` from setting, drop `.to_i`.
- `app/controllers/escalated/widget_controller.rb` ~81 — same.
- `app/services/escalated/automation_runner.rb` ~56 — `assigned_to: value.to_i` → `assigned_to: value`.
- `app/services/escalated/workflow_engine.rb` ~137 — `assigned_to: value.to_i` → `assigned_to: value`.
- `lib/escalated/services/automation_runner.rb` ~56 — same as above (duplicate).
- `lib/escalated/services/inbound_email_service.rb` ~189 — `guest_user_id` setting, drop `.to_i`.

Do NOT remove `.to_i` from genuinely-integer values (hours, counts, internal ids).

## Step 4 — Test

Add `spec/escalated/user_id_type_spec.rb` (or test/ if Minitest — match the
repo's existing test framework). Cover:
- `Escalated.user_id_type` defaults to `:bigint` when config is `:auto` and the
  user model has an integer PK.
- setting `Escalated.configuration.user_id_type = :uuid` makes it return `:uuid`.
Restore config after each example.

## Step 5 — Lint, test, commit

NOTE: this repo's RuboCop main branch has PRE-EXISTING lint debt — only ensure
you introduce NO NEW offenses in files you touch; do not try to fix unrelated
pre-existing offenses. Run from repo root and make tests green:

```
bundle exec rspec   # or: bin/rails test  — whichever the repo uses
bundle exec rubocop <files you changed>
```

Then commit (do NOT push):

```
git add -A
git commit -m "fix(users): support UUID/string host user keys"
```

Do NOT delete UUID_FIX_SPEC.md. Report every file changed and the final
test/lint status, and explicitly call out any pre-existing failures vs ones you
introduced.
