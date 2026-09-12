# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- **Configurable database connection.** `Escalated.configuration.database_connection` names the database Escalated's own tables live on. `nil` keeps the host application's primary connection, which is the historical behaviour and leaves an unconfigured host unchanged.

  Accepts either shape Rails offers: a Symbol/String establishes that `database.yml` entry directly, and a Hash is passed to `connects_to` so a host already using role-based multiple databases keeps its reading/writing split.

  Every Escalated model inherits `Escalated::ApplicationRecord`, so one setting moves all of them together; a spec enumerates `app/models/escalated` and fails if a model is ever added that does not inherit it. The long-running import checkout now takes Escalated's pool rather than `ActiveRecord::Base`'s, which would otherwise hold the wrong connection open for the whole import.

  Your user table is deliberately not moved — it belongs to the host, and Escalated stores host user ids as plain unconstrained columns so the two can live on different connections with no foreign key to span them.

  Migrations follow Rails' own rule: install them into the migration path for that database (`MIGRATIONS_PATH=db/support_migrate`) and run `db:migrate:support`. See the README.

### Added
- Consume central translations from the `escalated-locale` gem; plugin-local `config/locales/*.yml` and a new `config/locales/overrides/` directory still override central keys (last-loaded wins)
- SAML and JWT validation in SSO service
- Full automation system matching Laravel AutomationRunner
- Ticket type validation, scope, and controller filtering
- Permission seed with default roles
- Plugin bridge for Rails backend
- Import framework ported from Laravel
- `show_powered_by` setting
- Platform parity with Laravel (phases 1-5)
- Multi-language (i18n) support with EN, ES, FR, DE translations
- WordPress-style plugin/extension system with gem discovery and source badges
- REST API layer with token auth, rate limiting, and full ticket CRUD
- RSpec test suite
- GitHub Actions CI build pipeline
- Plugin SDK section and plugin authoring guide
- Inertia UI optional with `ui_enabled` config

### Fixed
- Reject webhooks when auth credentials are missing

## [0.4.0] - 2026-02-09

### Added
- Bulk actions for assigning, changing status/priority, adding tags, closing, or deleting multiple tickets
- Macros for reusable multi-step automations
- Ticket followers with shared notifications
- Satisfaction ratings (1-5 star CSAT) with optional comments
- Pinned internal notes
- Keyboard shortcuts for power users
- Quick filter chips (My Tickets, Unassigned, Urgent, SLA Breaching)
- Presence indicators for real-time ticket viewing
- Enhanced dashboard with CSAT metrics, resolution times, and SLA breach tracking

## [0.1.9] - 2026-02-08

### Security
- Fix SSRF, XSS, auth bypass, sort injection, and credential exposure vulnerabilities

## [0.1.8] - 2026-02-08

### Added
- Inbound email system with Mailgun, Postmark, AWS SES, and IMAP adapters
- Admin settings for inbound email configuration

## [0.1.7] - 2026-02-08

### Added
- Initial release of Escalated Rails engine
- Admin ticket management and configurable reference prefix
- EscalatedSettings model and guest ticket support
- Frontend assets moved to `@escalated-dev/escalated` npm package
- EscalatedPlugin theming with layout integration
