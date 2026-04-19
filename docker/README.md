# Escalated Rails — Docker demo (scaffold, not end-to-end)

Draft scaffold. `docker compose up --build` bootstraps a Rails 7.1 skeleton via `rails new` in the build stage, adds the gem via `bundle add escalated --path /package`, then runs `bin/rails db:prepare` on boot.

**Not verified end-to-end yet.** Missing pieces:

- Rails engine mount in `config/routes.rb` (`mount Escalated::Engine => '/support'`)
- User model + agent/admin flags + seeding
- Pundit policy stubs if the gem assumes they exist
- `/demo` picker route + session-based click-to-login controller
- Inertia/Vue asset pipeline for the bundle's pages

See the PR body for the full punch list.
