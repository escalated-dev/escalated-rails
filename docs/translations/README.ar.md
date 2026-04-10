<p align="center">
  <b>العربية</b> •
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
  <a href="README.ru.md">Русский</a> •
  <a href="README.tr.md">Türkçe</a> •
  <a href="README.zh-CN.md">简体中文</a>
</p>

# Escalated for Rails

[![Tests](https://github.com/escalated-dev/escalated-rails/actions/workflows/run-tests.yml/badge.svg)](https://github.com/escalated-dev/escalated-rails/actions/workflows/run-tests.yml)
[![Ruby](https://img.shields.io/badge/ruby-3.1+-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/rails-7.0+-D30001?logo=rubyonrails&logoColor=white)](https://rubyonrails.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

نظام تذاكر دعم متكامل وقابل للتضمين في Rails. أضفه إلى أي تطبيق — واحصل على مكتب مساعدة كامل مع تتبع SLA وقواعد التصعيد وسير عمل الوكلاء وبوابة العملاء. لا حاجة لخدمات خارجية.

> **[escalated.dev](https://escalated.dev)** — اعرف المزيد، شاهد العروض التوضيحية، وقارن بين خيارات السحابة والاستضافة الذاتية.

**ثلاثة أوضاع استضافة.** تشغيل مستضاف ذاتياً بالكامل، أو مزامنة مع سحابة مركزية لرؤية متعددة التطبيقات، أو توجيه كل شيء إلى السحابة. التبديل بين الأوضاع بتغيير إعداد واحد.

## الميزات

- **دورة حياة التذكرة** — إنشاء، تعيين، رد، حل، إغلاق، إعادة فتح مع انتقالات حالة قابلة للتهيئة
- **محرك SLA** — أهداف الاستجابة والحل حسب الأولوية، حساب ساعات العمل، كشف تلقائي للانتهاكات
- **قواعد التصعيد** — قواعد قائمة على الشروط تقوم بالتصعيد وإعادة الترتيب وإعادة التعيين أو الإشعار تلقائياً
- **لوحة تحكم الوكيل** — قائمة انتظار التذاكر مع فلاتر، إجراءات جماعية، ملاحظات داخلية، ردود جاهزة
- **بوابة العملاء** — إنشاء تذاكر ذاتية الخدمة، ردود، وتتبع الحالة
- **لوحة الإدارة** — إدارة الأقسام، سياسات SLA، قواعد التصعيد، العلامات وعرض التقارير
- **مرفقات الملفات** — رفع بالسحب والإفلات مع تخزين قابل للتهيئة وحدود الحجم
- **الجدول الزمني للنشاط** — سجل تدقيق كامل لكل إجراء على كل تذكرة
- **إشعارات البريد الإلكتروني** — إشعارات قابلة للتهيئة لكل حدث مع دعم webhook
- **توجيه الأقسام** — تنظيم الوكلاء في أقسام مع التعيين التلقائي (round-robin)
- **نظام العلامات** — تصنيف التذاكر بعلامات ملونة
- **تذاكر الضيوف** — إرسال تذاكر مجهول مع وصول بالرابط السحري عبر رمز الضيف
- **البريد الوارد** — إنشاء والرد على التذاكر عبر البريد الإلكتروني (Mailgun, Postmark, AWS SES, IMAP)
- **Inertia.js + Vue 3 UI** — واجهة أمامية مشتركة عبر [`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated)
- **تقسيم التذاكر** — تقسيم رد إلى تذكرة مستقلة جديدة مع الحفاظ على السياق الأصلي
- **Ticket snooze** — تأجيل التذاكر بإعدادات مسبقة (1 ساعة، 4 ساعات، غداً، الأسبوع القادم)؛ `rake escalated:wake_snoozed_tickets` يوقظها تلقائياً حسب الجدول
- **العروض المحفوظة / الطوابير المخصصة** — حفظ وتسمية ومشاركة إعدادات الفلاتر كعروض تذاكر قابلة لإعادة الاستخدام
- **عنصر الدعم القابل للتضمين** — عنصر `<script>` خفيف مع بحث قاعدة المعرفة ونموذج تذكرة وفحص الحالة
- **ترابط البريد الإلكتروني** — الرسائل الصادرة تتضمن رؤوس `In-Reply-To` و `References` الصحيحة للترابط الصحيح في عملاء البريد
- **قوالب بريد إلكتروني مع العلامة التجارية** — شعار ولون رئيسي ونص تذييل قابل للتهيئة لجميع الرسائل الصادرة
- **Real-time broadcasting** — بث اختياري عبر ActionCable مع استطلاع احتياطي تلقائي
- **مفتاح قاعدة المعرفة** — تفعيل أو تعطيل قاعدة المعرفة العامة من إعدادات الإدارة

## المتطلبات

- Ruby 3.1+
- Rails 7.1+
- Node.js 18+ (لأصول الواجهة الأمامية)

## البدء السريع

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

## إعداد الواجهة الأمامية

يستخدم Escalated إطار Inertia.js مع Vue 3. يتم توفير مكونات الواجهة الأمامية بواسطة حزمة npm [`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated).

### محتوى Tailwind

أضف حزمة Escalated إلى إعداد `content` في Tailwind حتى لا يتم حذف فئاتها:

```js
// tailwind.config.js
content: [
    // ... your existing paths
    './node_modules/@escalated-dev/escalated/src/**/*.vue',
],
```

### محلل الصفحات

أضف صفحات Escalated إلى محلل صفحات Inertia الخاص بك:

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

### التخصيص (اختياري)

قم بتسجيل `EscalatedPlugin` لعرض صفحات Escalated داخل تخطيط تطبيقك — لا حاجة لتكرار الصفحات:

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

راجع [ملف `@escalated-dev/escalated` README](https://github.com/escalated-dev/escalated) للحصول على وثائق السمات الكاملة وخصائص CSS المخصصة.

## أوضاع الاستضافة

### Self-Hosted (الافتراضي)

كل شيء يبقى في قاعدة بياناتك. لا اتصالات خارجية. استقلالية كاملة.

```ruby
Escalated.configure do |config|
  config.mode = :self_hosted
end
```

### متزامن

قاعدة بيانات محلية + مزامنة تلقائية مع `cloud.escalated.dev` لصندوق وارد موحد عبر تطبيقات متعددة. إذا كانت السحابة غير قابلة للوصول، يستمر تطبيقك في العمل — الأحداث تُوضع في قائمة الانتظار ويُعاد المحاولة.

```ruby
Escalated.configure do |config|
  config.mode = :synced
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

### السحابة

جميع بيانات التذاكر تُوجَّه عبر واجهة API السحابية. تطبيقك يتعامل مع المصادقة ويعرض الواجهة، لكن التخزين يكون في السحابة.

```ruby
Escalated.configure do |config|
  config.mode = :cloud
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

تشترك جميع الأوضاع الثلاثة في نفس وحدات التحكم وواجهة المستخدم ومنطق الأعمال. نمط المحرك يتعامل مع الباقي.

## التهيئة

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

## الجدولة

أضف هذه إلى المجدول الخاص بك لأتمتة SLA والتصعيد:

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

## المسارات

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

## الأحداث

Connect to ticket lifecycle events via ActiveSupport::Notifications:

```ruby
ActiveSupport::Notifications.subscribe("escalated.ticket_created") do |event|
  ticket = event.payload[:ticket]
  # Handle new ticket
end
```

## البريد الإلكتروني الوارد

Create and reply to tickets from incoming emails. Supports **Mailgun**, **Postmark**, **AWS SES** webhooks, and **IMAP** polling.

### تفعيل

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

### عناوين URL للـ Webhooks

| Provider | URL |
|----------|-----|
| Mailgun | `POST /support/inbound/mailgun` |
| Postmark | `POST /support/inbound/postmark` |
| AWS SES | `POST /support/inbound/ses` |

### استطلاع IMAP

Schedule `Escalated::PollImapJob` with Solid Queue, Sidekiq, or whenever:

```ruby
# config/recurring.yml (Solid Queue)
poll_imap:
  class: Escalated::PollImapJob
  schedule: every minute
```

### الميزات

- Thread detection via subject reference and `In-Reply-To` / `References` headers
- Guest tickets for unknown senders with auto-derived display names
- Auto-reopen resolved/closed tickets on email reply
- Duplicate detection via `Message-ID` headers
- Attachment handling with configurable size and count limits
- Audit logging of every inbound email
- All settings configurable from admin panel with env fallback

## SDK الإضافات

يدعم Escalated إضافات مستقلة عن إطار العمل مبنية بـ [Plugin SDK](https://github.com/escalated-dev/escalated-plugin-sdk). تُكتب الإضافات مرة واحدة بـ TypeScript وتعمل عبر جميع خلفيات Escalated.

### المتطلبات

- Node.js 20+
- `@escalated-dev/plugin-runtime` installed in your project

### تثبيت الإضافات

```bash
npm install @escalated-dev/plugin-runtime
npm install @escalated-dev/plugin-slack
npm install @escalated-dev/plugin-jira
```

### تفعيل إضافات SDK

```ruby
# config/initializers/escalated.rb
Escalated.configure do |config|
  # ... existing config ...
  config.sdk_plugins_enabled = true
end
```

### كيف يعمل

SDK plugins run as a long-lived Node.js subprocess managed by `@escalated-dev/plugin-runtime`, communicating with Rails over JSON-RPC 2.0 via stdio. The subprocess is spawned lazily on first use and automatically restarted with exponential backoff if it crashes. Every ticket lifecycle event is dual-dispatched to both Rails event handlers and the plugin runtime.

### بناء الإضافة الخاصة بك

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

### الموارد

- [Plugin SDK](https://github.com/escalated-dev/escalated-plugin-sdk) — حزمة تطوير TypeScript لبناء الإضافات
- [Plugin Runtime](https://github.com/escalated-dev/escalated-plugin-runtime) — مضيف وقت التشغيل للإضافات
- [Plugin Development Guide](https://github.com/escalated-dev/escalated-docs) — التوثيق الكامل

## متوفر أيضاً لـ

- **[Escalated for Laravel](https://github.com/escalated-dev/escalated-laravel)** — حزمة Laravel Composer
- **[Escalated for Rails](https://github.com/escalated-dev/escalated-rails)** — محرك Ruby on Rails (أنت هنا)
- **[Escalated for Django](https://github.com/escalated-dev/escalated-django)** — تطبيق Django قابل لإعادة الاستخدام
- **[Escalated for AdonisJS](https://github.com/escalated-dev/escalated-adonis)** — حزمة AdonisJS v6
- **[Escalated for Filament](https://github.com/escalated-dev/escalated-filament)** — إضافة لوحة إدارة Filament v3
- **[Shared Frontend](https://github.com/escalated-dev/escalated)** — مكونات واجهة المستخدم Vue 3 + Inertia.js

نفس البنية، نفس واجهة Vue، نفس أوضاع الاستضافة الثلاثة — لكل إطار عمل خلفي رئيسي.

## الاختبارات

```bash
bundle exec rspec
```

## الرخصة

MIT
