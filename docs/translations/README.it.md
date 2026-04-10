<p align="center">
  <a href="README.ar.md">العربية</a> •
  <a href="README.de.md">Deutsch</a> •
  <a href="../../README.md">English</a> •
  <a href="README.es.md">Español</a> •
  <a href="README.fr.md">Français</a> •
  <b>Italiano</b> •
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
[![Ruby](https://img.shields.io/badge/ruby-3.1+-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/rails-7.0+-D30001?logo=rubyonrails&logoColor=white)](https://rubyonrails.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Un sistema di ticket di supporto completo e integrabile per Rails. Aggiungilo a qualsiasi app — ottieni un helpdesk completo con tracciamento SLA, regole di escalation, flussi di lavoro degli agenti e un portale clienti. Nessun servizio esterno richiesto.

> **[escalated.dev](https://escalated.dev)** — Scopri di più, guarda le demo e confronta le opzioni Cloud vs Self-Hosted.

**Tre modalità di hosting.** Esecuzione completamente self-hosted, sincronizzazione con un cloud centrale per la visibilità multi-app, o proxy di tutto verso il cloud. Cambio modalità con una singola modifica alla configurazione.

## Funzionalità

- **Ciclo di vita del ticket** — Creare, assegnare, rispondere, risolvere, chiudere, riaprire con transizioni di stato configurabili
- **Motore SLA** — Obiettivi di risposta e risoluzione per priorità, calcolo delle ore lavorative, rilevamento automatico delle violazioni
- **Regole di escalation** — Regole basate su condizioni che escalano, ripriorizzano, riassegnano o notificano automaticamente
- **Dashboard dell'agente** — Coda ticket con filtri, azioni di massa, note interne, risposte predefinite
- **Portale clienti** — Creazione ticket self-service, risposte e tracciamento dello stato
- **Pannello di amministrazione** — Gestire reparti, policy SLA, regole di escalation, tag e visualizzare report
- **Allegati** — Upload drag-and-drop con archiviazione configurabile e limiti di dimensione
- **Timeline delle attività** — Log di audit completo di ogni azione su ogni ticket
- **Notifiche email** — Notifiche configurabili per evento con supporto webhook
- **Routing per reparto** — Organizzare gli agenti in reparti con assegnazione automatica (round-robin)
- **Sistema di tagging** — Categorizzare i ticket con tag colorati
- **Ticket ospiti** — Invio anonimo di ticket con accesso tramite link magico via token ospite
- **Email in entrata** — Creare e rispondere ai ticket via email (Mailgun, Postmark, AWS SES, IMAP)
- **Inertia.js + Vue 3 UI** — Frontend condiviso tramite [`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated)
- **Divisione ticket** — Dividere una risposta in un nuovo ticket autonomo preservando il contesto originale
- **Ticket snooze** — Sospendi i ticket con preimpostazioni (1h, 4h, domani, prossima settimana); `rake escalated:wake_snoozed_tickets` li riattiva automaticamente
- **Viste salvate / code personalizzate** — Salvare, denominare e condividere preset di filtri come viste ticket riutilizzabili
- **Widget di supporto integrabile** — Widget leggero `<script>` con ricerca KB, modulo ticket e verifica stato
- **Threading email** — Le email in uscita includono gli header `In-Reply-To` e `References` per un threading corretto nei client di posta
- **Template email personalizzati** — Logo, colore primario e testo del footer configurabili per tutte le email in uscita
- **Real-time broadcasting** — Broadcasting opzionale tramite ActionCable con fallback automatico al polling
- **Toggle base di conoscenza** — Abilitare o disabilitare la base di conoscenza pubblica dalle impostazioni admin

## Requisiti

- Ruby 3.1+
- Rails 7.1+
- Node.js 18+ (per le risorse frontend)

## Avvio Rapido

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

## Configurazione Frontend

Escalated utilizza Inertia.js con Vue 3. I componenti frontend sono forniti dal pacchetto npm [`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated).

### Contenuto Tailwind

Aggiungi il pacchetto Escalated alla configurazione `content` di Tailwind affinché le sue classi non vengano rimosse:

```js
// tailwind.config.js
content: [
    // ... your existing paths
    './node_modules/@escalated-dev/escalated/src/**/*.vue',
],
```

### Risolutore di Pagine

Aggiungi le pagine Escalated al tuo resolver delle pagine Inertia:

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

### Temi (Opzionale)

Registra l'`EscalatedPlugin` per renderizzare le pagine Escalated all'interno del layout della tua app — nessuna duplicazione di pagine necessaria:

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

Consulta il [README di `@escalated-dev/escalated`](https://github.com/escalated-dev/escalated) per la documentazione completa sui temi e le proprietà CSS personalizzate.

## Modalità di Hosting

### Self-Hosted (predefinito)

Tutto rimane nel tuo database. Nessuna chiamata esterna. Piena autonomia.

```ruby
Escalated.configure do |config|
  config.mode = :self_hosted
end
```

### Sincronizzato

Database locale + sincronizzazione automatica con `cloud.escalated.dev` per una casella di posta unificata su più app. Se il cloud non è raggiungibile, la tua app continua a funzionare — gli eventi vengono messi in coda e riprovati.

```ruby
Escalated.configure do |config|
  config.mode = :synced
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

### Cloud

Tutti i dati dei ticket vengono inviati all'API cloud. La tua app gestisce l'autenticazione e renderizza l'interfaccia, ma l'archiviazione risiede nel cloud.

```ruby
Escalated.configure do |config|
  config.mode = :cloud
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

Tutte e tre le modalità condividono gli stessi controller, l'interfaccia e la logica di business. Il pattern driver gestisce il resto.

## Configurazione

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

## Pianificazione

Aggiungi questi al tuo scheduler per l'automazione SLA e delle escalation:

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

## Percorsi

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

## Eventi

Connect to ticket lifecycle events via ActiveSupport::Notifications:

```ruby
ActiveSupport::Notifications.subscribe("escalated.ticket_created") do |event|
  ticket = event.payload[:ticket]
  # Handle new ticket
end
```

## Email in Entrata

Create and reply to tickets from incoming emails. Supports **Mailgun**, **Postmark**, **AWS SES** webhooks, and **IMAP** polling.

### Abilitare

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

### URL dei Webhooks

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

### Funzionalità

- Thread detection via subject reference and `In-Reply-To` / `References` headers
- Guest tickets for unknown senders with auto-derived display names
- Auto-reopen resolved/closed tickets on email reply
- Duplicate detection via `Message-ID` headers
- Attachment handling with configurable size and count limits
- Audit logging of every inbound email
- All settings configurable from admin panel with env fallback

## SDK Plugin

Escalated supporta plugin indipendenti dal framework costruiti con il [Plugin SDK](https://github.com/escalated-dev/escalated-plugin-sdk). I plugin vengono scritti una volta in TypeScript e funzionano su tutti i backend Escalated.

### Requisiti

- Node.js 20+
- `@escalated-dev/plugin-runtime` installed in your project

### Installazione dei Plugin

```bash
npm install @escalated-dev/plugin-runtime
npm install @escalated-dev/plugin-slack
npm install @escalated-dev/plugin-jira
```

### Abilitazione Plugin SDK

```ruby
# config/initializers/escalated.rb
Escalated.configure do |config|
  # ... existing config ...
  config.sdk_plugins_enabled = true
end
```

### Come Funziona

SDK plugins run as a long-lived Node.js subprocess managed by `@escalated-dev/plugin-runtime`, communicating with Rails over JSON-RPC 2.0 via stdio. The subprocess is spawned lazily on first use and automatically restarted with exponential backoff if it crashes. Every ticket lifecycle event is dual-dispatched to both Rails event handlers and the plugin runtime.

### Creare il Proprio Plugin

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

### Risorse

- [Plugin SDK](https://github.com/escalated-dev/escalated-plugin-sdk) — SDK TypeScript per creare plugin
- [Plugin Runtime](https://github.com/escalated-dev/escalated-plugin-runtime) — Host runtime per i plugin
- [Plugin Development Guide](https://github.com/escalated-dev/escalated-docs) — Documentazione completa

## Disponibile Anche Per

- **[Escalated for Laravel](https://github.com/escalated-dev/escalated-laravel)** — Pacchetto Laravel Composer
- **[Escalated for Rails](https://github.com/escalated-dev/escalated-rails)** — Motore Ruby on Rails (sei qui)
- **[Escalated for Django](https://github.com/escalated-dev/escalated-django)** — App Django riutilizzabile
- **[Escalated for AdonisJS](https://github.com/escalated-dev/escalated-adonis)** — Pacchetto AdonisJS v6
- **[Escalated for Filament](https://github.com/escalated-dev/escalated-filament)** — Plugin pannello admin Filament v3
- **[Shared Frontend](https://github.com/escalated-dev/escalated)** — Componenti UI Vue 3 + Inertia.js

Stessa architettura, stessa interfaccia Vue, stesse tre modalità di hosting — per ogni framework backend principale.

## Test

```bash
bundle exec rspec
```

## Licenza

MIT
