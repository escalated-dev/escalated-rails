<p align="center">
  <a href="README.ar.md">العربية</a> •
  <a href="README.de.md">Deutsch</a> •
  <a href="../../README.md">English</a> •
  <a href="README.es.md">Español</a> •
  <a href="README.fr.md">Français</a> •
  <a href="README.it.md">Italiano</a> •
  <a href="README.ja.md">日本語</a> •
  <a href="README.ko.md">한국어</a> •
  <a href="README.nl.md">Nederlands</a> •
  <a href="README.pl.md">Polski</a> •
  <a href="README.pt-BR.md">Português (BR)</a> •
  <b>Русский</b> •
  <a href="README.tr.md">Türkçe</a> •
  <a href="README.zh-CN.md">简体中文</a>
</p>

# Escalated for Rails

[![Tests](https://github.com/escalated-dev/escalated-rails/actions/workflows/run-tests.yml/badge.svg)](https://github.com/escalated-dev/escalated-rails/actions/workflows/run-tests.yml)
[![FOSSA Status](https://app.fossa.com/api/projects/custom%2B62107%2Fgithub.com%2Fescalated-dev%2Fescalated-rails.svg?type=shield)](https://app.fossa.com/projects/custom%2B62107%2Fgithub.com%2Fescalated-dev%2Fescalated-rails?ref=badge_shield)
[![Ruby](https://img.shields.io/badge/ruby-3.1+-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/rails-7.0+-D30001?logo=rubyonrails&logoColor=white)](https://rubyonrails.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Полнофункциональная встраиваемая система тикетов поддержки для Rails. Добавьте её в любое приложение — получите полноценный хелпдеск с отслеживанием SLA, правилами эскалации, рабочими процессами агентов и клиентским порталом. Внешние сервисы не требуются.

> **[escalated.dev](https://escalated.dev)** — Узнайте больше, посмотрите демо и сравните варианты Cloud и Self-Hosted.

**Три режима хостинга.** Полностью самостоятельный хостинг, синхронизация с центральным облаком для видимости нескольких приложений или проксирование всего в облако. Переключение режимов одним изменением конфигурации.

## Возможности

- **Жизненный цикл тикета** — Создание, назначение, ответ, решение, закрытие, повторное открытие с настраиваемыми переходами статусов
- **Движок SLA** — Цели ответа и решения по приоритетам, расчёт рабочих часов, автоматическое обнаружение нарушений
- **Правила эскалации** — Правила на основе условий для автоматической эскалации, смены приоритета, переназначения или уведомления
- **Панель агента** — Очередь тикетов с фильтрами, массовые действия, внутренние заметки, шаблонные ответы
- **Клиентский портал** — Самостоятельное создание тикетов, ответы и отслеживание статуса
- **Панель администратора** — Управление отделами, политиками SLA, правилами эскалации, тегами и просмотр отчётов
- **Вложения файлов** — Загрузка перетаскиванием с настраиваемым хранилищем и ограничениями размера
- **Хронология активности** — Полный журнал аудита каждого действия по каждому тикету
- **Уведомления по email** — Настраиваемые уведомления по событиям с поддержкой вебхуков
- **Маршрутизация по отделам** — Организация агентов по отделам с автоназначением (round-robin)
- **Система тегов** — Категоризация тикетов с помощью цветных тегов
- **Гостевые тикеты** — Анонимная подача тикетов с доступом по магической ссылке через гостевой токен
- **Входящая почта** — Создание и ответ на тикеты по email (Mailgun, Postmark, AWS SES, IMAP)
- **Inertia.js + Vue 3 UI** — Общий фронтенд через [`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated)
- **Разделение тикетов** — Выделение ответа в новый самостоятельный тикет с сохранением исходного контекста
- **Ticket snooze** — Откладывание тикетов с предустановками (1ч, 4ч, завтра, на следующей неделе); `rake escalated:wake_snoozed_tickets` автоматически пробуждает их по расписанию
- **Сохранённые представления / пользовательские очереди** — Сохранение, именование и обмен пресетами фильтров как повторно используемыми представлениями тикетов
- **Встраиваемый виджет поддержки** — Лёгкий `<script>` виджет с поиском по KB, формой тикета и проверкой статуса
- **Потоки электронной почты** — Исходящие письма включают корректные заголовки `In-Reply-To` и `References` для правильной группировки в почтовых клиентах
- **Брендированные шаблоны писем** — Настраиваемый логотип, основной цвет и текст нижнего колонтитула для всех исходящих писем
- **Real-time broadcasting** — Опциональная трансляция через ActionCable с автоматическим откатом на опрос
- **Переключатель базы знаний** — Включение или отключение публичной базы знаний из настроек администратора

## Требования

- Ruby 3.1+
- Rails 7.1+
- Node.js 18+ (для фронтенд-ресурсов)

## Быстрый Старт

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

## Настройка Фронтенда

Escalated использует Inertia.js с Vue 3. Фронтенд-компоненты предоставляются npm-пакетом [`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated).

### Контент Tailwind

Добавьте пакет Escalated в конфигурацию `content` Tailwind, чтобы его классы не были удалены:

```js
// tailwind.config.js
content: [
    // ... your existing paths
    './node_modules/@escalated-dev/escalated/src/**/*.vue',
],
```

### Резолвер Страниц

Добавьте страницы Escalated в ваш резолвер страниц Inertia:

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

### Темизация (Опционально)

Зарегистрируйте `EscalatedPlugin` для рендеринга страниц Escalated внутри макета вашего приложения — дублирование страниц не требуется:

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

См. [README `@escalated-dev/escalated`](https://github.com/escalated-dev/escalated) для полной документации по темам и пользовательским свойствам CSS.

## Режимы Размещения

### Self-Hosted (по умолчанию)

Всё остаётся в вашей базе данных. Никаких внешних вызовов. Полная автономия.

```ruby
Escalated.configure do |config|
  config.mode = :self_hosted
end
```

### Синхронизированный

Локальная база данных + автоматическая синхронизация с `cloud.escalated.dev` для единого почтового ящика на нескольких приложениях. Если облако недоступно, ваше приложение продолжает работать — события ставятся в очередь и повторяются.

```ruby
Escalated.configure do |config|
  config.mode = :synced
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

### Облако

Все данные тикетов проксируются через облачный API. Ваше приложение обрабатывает аутентификацию и рендерит UI, но хранилище находится в облаке.

```ruby
Escalated.configure do |config|
  config.mode = :cloud
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

Все три режима используют одни и те же контроллеры, интерфейс и бизнес-логику. Паттерн драйвера обрабатывает остальное.

## Конфигурация

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

## Планирование

Добавьте эти задачи в ваш планировщик для автоматизации SLA и эскалации:

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

## Маршруты

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

## События

Connect to ticket lifecycle events via ActiveSupport::Notifications:

```ruby
ActiveSupport::Notifications.subscribe("escalated.ticket_created") do |event|
  ticket = event.payload[:ticket]
  # Handle new ticket
end
```

## Входящая Электронная Почта

Create and reply to tickets from incoming emails. Supports **Mailgun**, **Postmark**, **AWS SES** webhooks, and **IMAP** polling.

### Включить

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

### URL-адреса Webhooks

| Provider | URL |
|----------|-----|
| Mailgun | `POST /support/inbound/mailgun` |
| Postmark | `POST /support/inbound/postmark` |
| AWS SES | `POST /support/inbound/ses` |

### Опрос IMAP

Schedule `Escalated::PollImapJob` with Solid Queue, Sidekiq, or whenever:

```ruby
# config/recurring.yml (Solid Queue)
poll_imap:
  class: Escalated::PollImapJob
  schedule: every minute
```

### Возможности

- Thread detection via subject reference and `In-Reply-To` / `References` headers
- Guest tickets for unknown senders with auto-derived display names
- Auto-reopen resolved/closed tickets on email reply
- Duplicate detection via `Message-ID` headers
- Attachment handling with configurable size and count limits
- Audit logging of every inbound email
- All settings configurable from admin panel with env fallback

## SDK Плагинов

Escalated поддерживает фреймворк-агностичные плагины, созданные с помощью [Plugin SDK](https://github.com/escalated-dev/escalated-plugin-sdk). Плагины пишутся один раз на TypeScript и работают на всех бэкендах Escalated.

### Требования

- Node.js 20+
- `@escalated-dev/plugin-runtime` installed in your project

### Установка Плагинов

```bash
npm install @escalated-dev/plugin-runtime
npm install @escalated-dev/plugin-slack
npm install @escalated-dev/plugin-jira
```

### Включение SDK Плагинов

```ruby
# config/initializers/escalated.rb
Escalated.configure do |config|
  # ... existing config ...
  config.sdk_plugins_enabled = true
end
```

### Как Это Работает

SDK plugins run as a long-lived Node.js subprocess managed by `@escalated-dev/plugin-runtime`, communicating with Rails over JSON-RPC 2.0 via stdio. The subprocess is spawned lazily on first use and automatically restarted with exponential backoff if it crashes. Every ticket lifecycle event is dual-dispatched to both Rails event handlers and the plugin runtime.

### Создание Собственного Плагина

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

### Ресурсы

- [Plugin SDK](https://github.com/escalated-dev/escalated-plugin-sdk) — TypeScript SDK для создания плагинов
- [Plugin Runtime](https://github.com/escalated-dev/escalated-plugin-runtime) — Хост среды выполнения для плагинов
- [Plugin Development Guide](https://github.com/escalated-dev/escalated-docs) — Полная документация

## Также Доступно Для

- **[Escalated for Laravel](https://github.com/escalated-dev/escalated-laravel)** — Пакет Laravel Composer
- **[Escalated for Rails](https://github.com/escalated-dev/escalated-rails)** — Движок Ruby on Rails (вы здесь)
- **[Escalated for Django](https://github.com/escalated-dev/escalated-django)** — Переиспользуемое приложение Django
- **[Escalated for AdonisJS](https://github.com/escalated-dev/escalated-adonis)** — Пакет AdonisJS v6
- **[Escalated for Filament](https://github.com/escalated-dev/escalated-filament)** — Плагин админ-панели Filament v3
- **[Shared Frontend](https://github.com/escalated-dev/escalated)** — Компоненты UI Vue 3 + Inertia.js

Та же архитектура, тот же Vue UI, те же три режима хостинга — для каждого основного бэкенд-фреймворка.

## Тестирование

```bash
bundle exec rspec
```

## Лицензия

MIT
