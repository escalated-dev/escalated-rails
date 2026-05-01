<p align="center">
  <a href="README.ar.md">العربية</a> •
  <a href="README.de.md">Deutsch</a> •
  <a href="../../README.md">English</a> •
  <a href="README.es.md">Español</a> •
  <b>Français</b> •
  <a href="README.it.md">Italiano</a> •
  <a href="README.ja.md">日本語</a> •
  <a href="README.ko.md">한국어</a> •
  <a href="README.nl.md">Nederlands</a> •
  <a href="README.pl.md">Polski</a> •
  <a href="README.pt-BR.md">Português (BR)</a> •
  <a href="README.ru.md">Русский</a> •
  <a href="README.tr.md">Türkçe</a> •
  <a href="README.zh-CN.md">简体中文</a>
</p>

# Escalated for Rails

[![Tests](https://github.com/escalated-dev/escalated-rails/actions/workflows/run-tests.yml/badge.svg)](https://github.com/escalated-dev/escalated-rails/actions/workflows/run-tests.yml)
[![FOSSA Status](https://app.fossa.com/api/projects/custom%2B62107%2Fgithub.com%2Fescalated-dev%2Fescalated-rails.svg?type=shield)](https://app.fossa.com/projects/custom%2B62107%2Fgithub.com%2Fescalated-dev%2Fescalated-rails?ref=badge_shield)
[![Ruby](https://img.shields.io/badge/ruby-3.1+-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/rails-7.0+-D30001?logo=rubyonrails&logoColor=white)](https://rubyonrails.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Un système de tickets de support complet et intégrable pour Rails. Intégrez-le dans n'importe quelle application — obtenez un helpdesk complet avec suivi des SLA, règles d'escalade, workflows des agents et un portail client. Aucun service externe requis.

> **[escalated.dev](https://escalated.dev)** — En savoir plus, voir les démos et comparer les options Cloud vs Auto-hébergé.

**Trois modes d'hébergement.** Exécution entièrement auto-hébergée, synchronisation avec un cloud central pour une visibilité multi-applications, ou proxy de tout vers le cloud. Changez de mode avec un simple changement de configuration.

## Fonctionnalités

- **Cycle de vie du ticket** — Créer, assigner, répondre, résoudre, fermer, rouvrir avec des transitions d'état configurables
- **Moteur SLA** — Objectifs de réponse et de résolution par priorité, calcul des heures ouvrées, détection automatique des violations
- **Règles d'escalade** — Règles basées sur des conditions qui escaladent, repriorisent, réassignent ou notifient automatiquement
- **Tableau de bord de l'agent** — File d'attente de tickets avec filtres, actions groupées, notes internes, réponses prédéfinies
- **Portail client** — Création de tickets en libre-service, réponses et suivi de l'état
- **Panneau d'administration** — Gérer les départements, politiques SLA, règles d'escalade, tags et consulter les rapports
- **Pièces jointes** — Téléversement par glisser-déposer avec stockage configurable et limites de taille
- **Chronologie d'activité** — Journal d'audit complet de chaque action sur chaque ticket
- **Notifications par email** — Notifications configurables par événement avec support webhook
- **Routage par département** — Organiser les agents en départements avec auto-assignation (round-robin)
- **Système de tags** — Catégoriser les tickets avec des tags colorés
- **Tickets invités** — Soumission anonyme de tickets avec accès par lien magique via token invité
- **Email entrant** — Créer et répondre aux tickets par email (Mailgun, Postmark, AWS SES, IMAP)
- **Inertia.js + Vue 3 UI** — Frontend partagé via [`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated)
- **Division de tickets** — Séparer une réponse en un nouveau ticket indépendant tout en préservant le contexte original
- **Ticket snooze** — Mettre en veille les tickets avec des préréglages (1h, 4h, demain, semaine prochaine) ; `rake escalated:wake_snoozed_tickets` les réactive automatiquement
- **Vues enregistrées / files personnalisées** — Enregistrer, nommer et partager des préréglages de filtres comme vues de tickets réutilisables
- **Widget de support intégrable** — Widget léger `<script>` avec recherche KB, formulaire de ticket et vérification d'état
- **Threading email** — Les emails sortants incluent les en-têtes `In-Reply-To` et `References` pour un threading correct dans les clients mail
- **Modèles d'email personnalisés** — Logo, couleur primaire et texte de pied de page configurables pour tous les emails sortants
- **Real-time broadcasting** — Diffusion optionnelle via ActionCable avec repli automatique sur le polling
- **Activation de la base de connaissances** — Activer ou désactiver la base de connaissances publique depuis les paramètres d'administration

## Prérequis

- Ruby 3.1+
- Rails 7.1+
- Node.js 18+ (pour les ressources frontend)

## Démarrage Rapide

```bash
bundle add escalated
npm install @escalated-dev/escalated
rails generate escalated:install
rails db:migrate
```

Add the `Ticketable` concern to your User model:

```ruby
class User < ApplicationRecord
  include Escalated::Ticketable
end
```

Define authorization in your `ApplicationController` or an initializer:

```ruby
# config/initializers/escalated.rb
Escalated.configure do |config|
  config.admin_check = ->(user) { user.admin? }
  config.agent_check = ->(user) { user.agent? || user.admin? }
end
```

Visit `/support` — you're live.

## Configuration du Frontend

Escalated utilise Inertia.js avec Vue 3. Les composants frontend sont fournis par le package npm [`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated).

### Contenu Tailwind

Ajoutez le package Escalated à la configuration `content` de Tailwind pour que ses classes ne soient pas purgées :

```js
// tailwind.config.js
content: [
    // ... your existing paths
    './node_modules/@escalated-dev/escalated/src/**/*.vue',
],
```

### Résolveur de Pages

Ajoutez les pages Escalated à votre résolveur de pages Inertia :

```javascript
// app/javascript/entrypoints/application.js
import { createApp, h } from 'vue'
import { createInertiaApp } from '@inertiajs/vue3'

createInertiaApp({
  resolve: name => {
    if (name.startsWith('Escalated/')) {
      const escalatedPages = import.meta.glob(
        '../../../node_modules/@escalated-dev/escalated/src/pages/**/*.vue',
        { eager: true }
      )
      const pageName = name.replace('Escalated/', '')
      return escalatedPages[`../../../node_modules/@escalated-dev/escalated/src/pages/${pageName}.vue`]
    }

    const pages = import.meta.glob('../pages/**/*.vue', { eager: true })
    return pages[`../pages/${name}.vue`]
  },
  setup({ el, App, props, plugin }) {
    createApp({ render: () => h(App, props) })
      .use(plugin)
      .mount(el)
  },
})
```

### Thème (Optionnel)

Enregistrez le `EscalatedPlugin` pour afficher les pages Escalated dans la mise en page de votre application — aucune duplication de pages nécessaire :

```javascript
import { EscalatedPlugin } from '@escalated-dev/escalated'
import AppLayout from '@/layouts/AppLayout.vue'

createInertiaApp({
  setup({ el, App, props, plugin }) {
    createApp({ render: () => h(App, props) })
      .use(plugin)
      .use(EscalatedPlugin, {
        layout: AppLayout,
        theme: {
          primary: '#3b82f6',
          radius: '0.75rem',
        }
      })
      .mount(el)
  },
})
```

Your layout component must accept a `#header` slot and a default slot. Escalated will render its sub-navigation in the header and page content in the default slot. Without the plugin, Escalated uses its own standalone layout.

Consultez le [README de `@escalated-dev/escalated`](https://github.com/escalated-dev/escalated) pour la documentation complète sur les thèmes et les propriétés CSS personnalisées.

## Modes d'Hébergement

### Self-Hosted (par défaut)

Tout reste dans votre base de données. Aucun appel externe. Autonomie totale.

```ruby
Escalated.configure do |config|
  config.mode = :self_hosted
end
```

### Synchronisé

Base de données locale + synchronisation automatique vers `cloud.escalated.dev` pour une boîte de réception unifiée sur plusieurs applications. Si le cloud est inaccessible, votre application continue de fonctionner — les événements sont mis en file d'attente et réessayés.

```ruby
Escalated.configure do |config|
  config.mode = :synced
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

### Cloud

Toutes les données de tickets sont proxifiées vers l'API cloud. Votre application gère l'authentification et affiche l'interface, mais le stockage réside dans le cloud.

```ruby
Escalated.configure do |config|
  config.mode = :cloud
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

Les trois modes partagent les mêmes contrôleurs, l'interface et la logique métier. Le pattern driver gère le reste.

## Configuration

Create or edit `config/initializers/escalated.rb`:

```ruby
Escalated.configure do |config|
  config.mode = :self_hosted
  config.user_class = "User"
  config.table_prefix = "escalated_"
  config.route_prefix = "support"
  config.default_priority = :medium

  # Middleware
  config.middleware = [:authenticate_user!]
  config.admin_middleware = nil

  # Tickets
  config.allow_customer_close = true
  config.auto_close_resolved_after_days = 7
  config.max_attachments_per_reply = 5
  config.max_attachment_size_kb = 10240

  # SLA
  config.sla = {
    enabled: true,
    business_hours_only: true,
    business_hours: {
      start: 9, end: 17,
      timezone: "UTC",
      working_days: [1, 2, 3, 4, 5]
    }
  }

  # Notifications
  config.notification_channels = [:email]
  config.webhook_url = nil

  # Storage (ActiveStorage)
  config.storage_service = :local
end
```

## Planification

Ajoutez-les à votre planificateur pour l'automatisation des SLA et des escalades :

```ruby
# config/schedule.rb (whenever gem) or use solid_queue/sidekiq-cron
every 1.minute do
  runner "Escalated::CheckSlaJob.perform_now"
end

every 5.minutes do
  runner "Escalated::EvaluateEscalationsJob.perform_now"
end

every 1.day do
  runner "Escalated::CloseResolvedJob.perform_now"
end

every 1.week do
  runner "Escalated::PurgeActivitiesJob.perform_now"
end
```

## Routes

Routes are automatically mounted when the engine loads. By default they mount at `/support`.

| Route | Method | Description |
|-------|--------|-------------|
| `/support` | GET | Customer ticket list |
| `/support/create` | GET | New ticket form |
| `/support/{ticket}` | GET | Ticket detail |
| `/support/agent` | GET | Agent dashboard |
| `/support/agent/tickets` | GET | Agent ticket queue |
| `/support/agent/tickets/{ticket}` | GET | Agent ticket view |
| `/support/admin/reports` | GET | Admin reports |
| `/support/admin/departments` | GET | Department management |
| `/support/admin/sla-policies` | GET | SLA policy management |
| `/support/admin/escalation-rules` | GET | Escalation rule management |
| `/support/admin/tags` | GET | Tag management |
| `/support/admin/canned-responses` | GET | Canned response management |
| `/support/agent/tickets/bulk` | POST | Bulk actions on multiple tickets |
| `/support/agent/tickets/{ticket}/follow` | POST | Follow/unfollow a ticket |
| `/support/agent/tickets/{ticket}/macro` | POST | Apply a macro to a ticket |
| `/support/agent/tickets/{ticket}/presence` | POST | Update presence on a ticket |
| `/support/agent/tickets/{ticket}/pin/{reply}` | POST | Pin/unpin an internal note |
| `/support/{ticket}/rate` | POST | Submit satisfaction rating |

## Événements

Connect to ticket lifecycle events via ActiveSupport::Notifications:

```ruby
ActiveSupport::Notifications.subscribe("escalated.ticket_created") do |event|
  ticket = event.payload[:ticket]
  # Handle new ticket
end
```

## Email Entrant

Create and reply to tickets from incoming emails. Supports **Mailgun**, **Postmark**, **AWS SES** webhooks, and **IMAP** polling.

### Activer

```ruby
# config/initializers/escalated.rb
Escalated.configure do |config|
  config.inbound_email_enabled = true
  config.inbound_email_adapter = :mailgun
  config.inbound_email_address = "support@yourapp.com"

  # Mailgun
  config.mailgun_signing_key = ENV["ESCALATED_MAILGUN_SIGNING_KEY"]

  # Postmark
  config.postmark_inbound_token = ENV["ESCALATED_POSTMARK_INBOUND_TOKEN"]

  # AWS SES
  config.ses_region = "us-east-1"
  config.ses_topic_arn = ENV["ESCALATED_SES_TOPIC_ARN"]

  # IMAP
  config.imap_host = ENV["ESCALATED_IMAP_HOST"]
  config.imap_port = 993
  config.imap_encryption = :ssl
  config.imap_username = ENV["ESCALATED_IMAP_USERNAME"]
  config.imap_password = ENV["ESCALATED_IMAP_PASSWORD"]
  config.imap_mailbox = "INBOX"
end
```

### URLs des Webhooks

| Provider | URL |
|----------|-----|
| Mailgun | `POST /support/inbound/mailgun` |
| Postmark | `POST /support/inbound/postmark` |
| AWS SES | `POST /support/inbound/ses` |

### Polling IMAP

Schedule `Escalated::PollImapJob` with Solid Queue, Sidekiq, or whenever:

```ruby
# config/recurring.yml (Solid Queue)
poll_imap:
  class: Escalated::PollImapJob
  schedule: every minute
```

### Fonctionnalités

- Thread detection via subject reference and `In-Reply-To` / `References` headers
- Guest tickets for unknown senders with auto-derived display names
- Auto-reopen resolved/closed tickets on email reply
- Duplicate detection via `Message-ID` headers
- Attachment handling with configurable size and count limits
- Audit logging of every inbound email
- All settings configurable from admin panel with env fallback

## SDK de Plugins

Escalated prend en charge des plugins indépendants du framework construits avec le [Plugin SDK](https://github.com/escalated-dev/escalated-plugin-sdk). Les plugins sont écrits une fois en TypeScript et fonctionnent sur tous les backends Escalated.

### Prérequis

- Node.js 20+
- `@escalated-dev/plugin-runtime` installed in your project

### Installation des Plugins

```bash
npm install @escalated-dev/plugin-runtime
npm install @escalated-dev/plugin-slack
npm install @escalated-dev/plugin-jira
```

### Activation des Plugins SDK

```ruby
# config/initializers/escalated.rb
Escalated.configure do |config|
  # ... existing config ...
  config.sdk_plugins_enabled = true
end
```

### Comment Ça Marche

SDK plugins run as a long-lived Node.js subprocess managed by `@escalated-dev/plugin-runtime`, communicating with Rails over JSON-RPC 2.0 via stdio. The subprocess is spawned lazily on first use and automatically restarted with exponential backoff if it crashes. Every ticket lifecycle event is dual-dispatched to both Rails event handlers and the plugin runtime.

### Créer Votre Propre Plugin

```typescript
import { definePlugin } from '@escalated-dev/plugin-sdk'

export default definePlugin({
  name: 'my-plugin',
  version: '1.0.0',
  actions: {
    'ticket.created': async (event, ctx) => {
      ctx.log.info('New ticket!', event)
    },
  },
})
```

### Ressources

- [Plugin SDK](https://github.com/escalated-dev/escalated-plugin-sdk) — SDK TypeScript pour créer des plugins
- [Plugin Runtime](https://github.com/escalated-dev/escalated-plugin-runtime) — Hôte d'exécution pour les plugins
- [Plugin Development Guide](https://github.com/escalated-dev/escalated-docs) — Documentation complète

## Également Disponible Pour

- **[Escalated for Laravel](https://github.com/escalated-dev/escalated-laravel)** — Package Laravel Composer
- **[Escalated for Rails](https://github.com/escalated-dev/escalated-rails)** — Moteur Ruby on Rails (vous êtes ici)
- **[Escalated for Django](https://github.com/escalated-dev/escalated-django)** — Application Django réutilisable
- **[Escalated for AdonisJS](https://github.com/escalated-dev/escalated-adonis)** — Package AdonisJS v6
- **[Escalated for Filament](https://github.com/escalated-dev/escalated-filament)** — Plugin panneau d'administration Filament v3
- **[Shared Frontend](https://github.com/escalated-dev/escalated)** — Composants UI Vue 3 + Inertia.js

Même architecture, même interface Vue, mêmes trois modes d'hébergement — pour chaque framework backend majeur.

## Tests

```bash
bundle exec rspec
```

## Licence

MIT
