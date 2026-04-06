# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
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
