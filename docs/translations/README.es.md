<p align="center">
  <a href="README.ar.md">العربية</a> •
  <a href="README.de.md">Deutsch</a> •
  <a href="../../README.md">English</a> •
  <b>Español</b> •
  <a href="README.fr.md">Français</a> •
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
[![Ruby](https://img.shields.io/badge/ruby-3.1+-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/rails-7.0+-D30001?logo=rubyonrails&logoColor=white)](https://rubyonrails.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Un sistema de tickets de soporte completo e integrable para Rails. Agrégalo a cualquier aplicación — obtén un helpdesk completo con seguimiento de SLA, reglas de escalamiento, flujos de trabajo de agentes y un portal de clientes. No requiere servicios externos.

> **[escalated.dev](https://escalated.dev)** — Obtenga más información, vea demos y compare las opciones de Cloud vs Auto-hospedado.

**Tres modos de alojamiento.** Ejecute completamente auto-hospedado, sincronice con una nube central para visibilidad multi-aplicación, o redirija todo a la nube. Cambie de modo con un solo cambio de configuración.

## Características

- **Ciclo de vida del ticket** — Crear, asignar, responder, resolver, cerrar, reabrir con transiciones de estado configurables
- **Motor de SLA** — Objetivos de respuesta y resolución por prioridad, cálculo de horas laborales, detección automática de incumplimientos
- **Reglas de escalamiento** — Reglas basadas en condiciones que escalan, repriorizan, reasignan o notifican automáticamente
- **Panel del agente** — Cola de tickets con filtros, acciones masivas, notas internas, respuestas predefinidas
- **Portal del cliente** — Creación de tickets en autoservicio, respuestas y seguimiento de estado
- **Panel de administración** — Gestionar departamentos, políticas de SLA, reglas de escalamiento, etiquetas y ver informes
- **Archivos adjuntos** — Carga con arrastrar y soltar, almacenamiento y límites de tamaño configurables
- **Línea de actividad** — Registro completo de auditoría de cada acción en cada ticket
- **Notificaciones por correo** — Notificaciones configurables por evento con soporte de webhooks
- **Enrutamiento por departamentos** — Organizar agentes en departamentos con asignación automática (round-robin)
- **Sistema de etiquetado** — Categorizar tickets con etiquetas de colores
- **Tickets de invitados** — Envío anónimo de tickets con acceso por enlace mágico vía token de invitado
- **Correo entrante** — Crear y responder tickets por correo electrónico (Mailgun, Postmark, AWS SES, IMAP)
- **Inertia.js + Vue 3 UI** — Frontend compartido a través de [`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated)
- **División de tickets** — Dividir una respuesta en un nuevo ticket independiente conservando el contexto original
- **Ticket snooze** — Posponer tickets con preajustes (1h, 4h, mañana, próxima semana); `rake escalated:wake_snoozed_tickets` los reactiva automáticamente según la programación
- **Vistas guardadas / colas personalizadas** — Guardar, nombrar y compartir filtros preestablecidos como vistas de tickets reutilizables
- **Widget de soporte integrable** — Widget ligero `<script>` con búsqueda en KB, formulario de tickets y verificación de estado
- **Hilos de correo electrónico** — Los correos salientes incluyen encabezados `In-Reply-To` y `References` apropiados para el hilo correcto en clientes de correo
- **Plantillas de correo con marca** — Logo, color primario y texto de pie de página configurables para todos los correos salientes
- **Real-time broadcasting** — Transmisión opcional a través de ActionCable con respaldo automático de sondeo
- **Interruptor de base de conocimientos** — Habilitar o deshabilitar la base de conocimientos pública desde la configuración de administración

## Requisitos

- Ruby 3.1+
- Rails 7.1+
- Node.js 18+ (para recursos del frontend)

## Inicio Rápido

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

## Configuración del Frontend

Escalated utiliza Inertia.js con Vue 3. Los componentes del frontend son proporcionados por el paquete npm [`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated).

### Contenido de Tailwind

Agregue el paquete Escalated a la configuración `content` de Tailwind para que sus clases no sean eliminadas:

```js
// tailwind.config.js
content: [
    // ... your existing paths
    './node_modules/@escalated-dev/escalated/src/**/*.vue',
],
```

### Resolución de Páginas

Agregue las páginas de Escalated a su resolver de páginas de Inertia:

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

### Temas (Opcional)

Registre el `EscalatedPlugin` para renderizar las páginas de Escalated dentro del diseño de su aplicación — no se necesita duplicación de páginas:

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

Consulte el [README de `@escalated-dev/escalated`](https://github.com/escalated-dev/escalated) para la documentación completa de temas y propiedades CSS personalizadas.

## Modos de Alojamiento

### Self-Hosted (predeterminado)

Todo permanece en su base de datos. Sin llamadas externas. Autonomía total.

```ruby
Escalated.configure do |config|
  config.mode = :self_hosted
end
```

### Sincronizado

Base de datos local + sincronización automática con `cloud.escalated.dev` para bandeja de entrada unificada en múltiples aplicaciones. Si la nube no está disponible, su aplicación sigue funcionando — los eventos se ponen en cola y se reintentan.

```ruby
Escalated.configure do |config|
  config.mode = :synced
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

### Nube

Todos los datos de tickets se envían a la API en la nube. Su aplicación maneja la autenticación y renderiza la interfaz, pero el almacenamiento vive en la nube.

```ruby
Escalated.configure do |config|
  config.mode = :cloud
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

Los tres modos comparten los mismos controladores, interfaz y lógica de negocio. El patrón de driver se encarga del resto.

## Configuración

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

## Programación

Agregue estos a su programador para la automatización de SLA y escalamiento:

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

## Rutas

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

## Eventos

Connect to ticket lifecycle events via ActiveSupport::Notifications:

```ruby
ActiveSupport::Notifications.subscribe("escalated.ticket_created") do |event|
  ticket = event.payload[:ticket]
  # Handle new ticket
end
```

## Correo Electrónico Entrante

Create and reply to tickets from incoming emails. Supports **Mailgun**, **Postmark**, **AWS SES** webhooks, and **IMAP** polling.

### Habilitar

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

### URLs de Webhooks

| Provider | URL |
|----------|-----|
| Mailgun | `POST /support/inbound/mailgun` |
| Postmark | `POST /support/inbound/postmark` |
| AWS SES | `POST /support/inbound/ses` |

### Sondeo IMAP

Schedule `Escalated::PollImapJob` with Solid Queue, Sidekiq, or whenever:

```ruby
# config/recurring.yml (Solid Queue)
poll_imap:
  class: Escalated::PollImapJob
  schedule: every minute
```

### Características

- Thread detection via subject reference and `In-Reply-To` / `References` headers
- Guest tickets for unknown senders with auto-derived display names
- Auto-reopen resolved/closed tickets on email reply
- Duplicate detection via `Message-ID` headers
- Attachment handling with configurable size and count limits
- Audit logging of every inbound email
- All settings configurable from admin panel with env fallback

## SDK de Plugins

Escalated soporta plugins agnósticos al framework construidos con el [Plugin SDK](https://github.com/escalated-dev/escalated-plugin-sdk). Los plugins se escriben una vez en TypeScript y funcionan en todos los backends de Escalated.

### Requisitos

- Node.js 20+
- `@escalated-dev/plugin-runtime` installed in your project

### Instalación de Plugins

```bash
npm install @escalated-dev/plugin-runtime
npm install @escalated-dev/plugin-slack
npm install @escalated-dev/plugin-jira
```

### Habilitando Plugins SDK

```ruby
# config/initializers/escalated.rb
Escalated.configure do |config|
  # ... existing config ...
  config.sdk_plugins_enabled = true
end
```

### Cómo Funciona

SDK plugins run as a long-lived Node.js subprocess managed by `@escalated-dev/plugin-runtime`, communicating with Rails over JSON-RPC 2.0 via stdio. The subprocess is spawned lazily on first use and automatically restarted with exponential backoff if it crashes. Every ticket lifecycle event is dual-dispatched to both Rails event handlers and the plugin runtime.

### Creando Tu Propio Plugin

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

### Recursos

- [Plugin SDK](https://github.com/escalated-dev/escalated-plugin-sdk) — SDK de TypeScript para crear plugins
- [Plugin Runtime](https://github.com/escalated-dev/escalated-plugin-runtime) — Host de tiempo de ejecución para plugins
- [Plugin Development Guide](https://github.com/escalated-dev/escalated-docs) — Documentación completa

## También Disponible Para

- **[Escalated for Laravel](https://github.com/escalated-dev/escalated-laravel)** — Paquete Laravel Composer
- **[Escalated for Rails](https://github.com/escalated-dev/escalated-rails)** — Motor Ruby on Rails (estás aquí)
- **[Escalated for Django](https://github.com/escalated-dev/escalated-django)** — Aplicación reutilizable de Django
- **[Escalated for AdonisJS](https://github.com/escalated-dev/escalated-adonis)** — Paquete AdonisJS v6
- **[Escalated for Filament](https://github.com/escalated-dev/escalated-filament)** — Plugin de panel de administración Filament v3
- **[Shared Frontend](https://github.com/escalated-dev/escalated)** — Componentes de UI Vue 3 + Inertia.js

Misma arquitectura, misma interfaz Vue, mismos tres modos de alojamiento — para cada framework backend importante.

## Pruebas

```bash
bundle exec rspec
```

## Licencia

MIT
