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
  <a href="README.ru.md">Русский</a> •
  <b>Türkçe</b> •
  <a href="README.zh-CN.md">简体中文</a>
</p>

# Escalated for Rails

[![Tests](https://github.com/escalated-dev/escalated-rails/actions/workflows/run-tests.yml/badge.svg)](https://github.com/escalated-dev/escalated-rails/actions/workflows/run-tests.yml)
[![Ruby](https://img.shields.io/badge/ruby-3.1+-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/rails-7.0+-D30001?logo=rubyonrails&logoColor=white)](https://rubyonrails.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Rails için tam özellikli, gömülebilir bir destek talep sistemi. Herhangi bir uygulamaya ekleyin — SLA takibi, eskalasyon kuralları, temsilci iş akışları ve müşteri portalı ile eksiksiz bir yardım masası elde edin. Harici hizmetler gerekmez.

> **[escalated.dev](https://escalated.dev)** — Daha fazla bilgi edinin, demoları görüntüleyin ve Bulut ile Kendi Sunucunuzda seçeneklerini karşılaştırın.

**Üç barındırma modu.** Tamamen kendi sunucunuzda çalıştırın, çoklu uygulama görünürlüğü için merkezi bir buluta senkronize edin veya her şeyi buluta yönlendirin. Tek bir yapılandırma değişikliğiyle modları değiştirin.

## Özellikler

- **Bilet yaşam döngüsü** — Yapılandırılabilir durum geçişleri ile oluşturma, atama, yanıtlama, çözme, kapatma, yeniden açma
- **SLA motoru** — Önceliğe göre yanıt ve çözüm hedefleri, iş saatleri hesaplaması, otomatik ihlal tespiti
- **Yükseltme kuralları** — Otomatik olarak yükselten, yeniden önceliklendiren, yeniden atayan veya bildirim gönderen koşul tabanlı kurallar
- **Temsilci paneli** — Filtreler, toplu işlemler, dahili notlar, hazır yanıtlar içeren bilet kuyruğu
- **Müşteri portalı** — Self-servis bilet oluşturma, yanıtlar ve durum takibi
- **Yönetim paneli** — Departmanları, SLA politikalarını, yükseltme kurallarını, etiketleri yönetin ve raporları görüntüleyin
- **Dosya ekleri** — Yapılandırılabilir depolama ve boyut limitleri ile sürükle-bırak yükleme
- **Etkinlik zaman çizelgesi** — Her biletteki her eylemin tam denetim günlüğü
- **E-posta bildirimleri** — Webhook desteği ile etkinlik bazında yapılandırılabilir bildirimler
- **Departman yönlendirme** — Temsilcileri departmanlara organize edin, otomatik atama (round-robin)
- **Etiketleme sistemi** — Biletleri renkli etiketlerle kategorize edin
- **Misafir biletleri** — Misafir tokeni ile sihirli bağlantı erişimli anonim bilet gönderimi
- **Gelen e-posta** — E-posta ile bilet oluşturma ve yanıtlama (Mailgun, Postmark, AWS SES, IMAP)
- **Inertia.js + Vue 3 UI** — Paylaşılan frontend [`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated) aracılığıyla
- **Bilet bölme** — Orijinal bağlamı koruyarak bir yanıtı yeni bağımsız bir bilete ayırma
- **Ticket snooze** — Ön ayarlı erteleme ile talepleri erteleyin (1 saat, 4 saat, yarın, gelecek hafta); `rake escalated:wake_snoozed_tickets` onları programa göre otomatik olarak uyandırır
- **Kayıtlı görünümler / özel kuyruklar** — Filtre ön ayarlarını yeniden kullanılabilir bilet görünümleri olarak kaydedin, adlandırın ve paylaşın
- **Gömülebilir destek widget'ı** — KB arama, bilet formu ve durum kontrolü içeren hafif `<script>` widget'ı
- **E-posta zincirleme** — Giden e-postalar, posta istemcilerinde doğru zincirleme için uygun `In-Reply-To` ve `References` başlıkları içerir
- **Markalı e-posta şablonları** — Tüm giden e-postalar için yapılandırılabilir logo, birincil renk ve altbilgi metni
- **Real-time broadcasting** — ActionCable ile isteğe bağlı yayın, otomatik yoklama geri dönüşü ile
- **Bilgi tabanı açma/kapama** — Yönetim ayarlarından herkese açık bilgi tabanını etkinleştirin veya devre dışı bırakın

## Gereksinimler

- Ruby 3.1+
- Rails 7.1+
- Node.js 18+ (frontend varlıkları için)

## Hızlı Başlangıç

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

## Frontend Kurulumu

Escalated, Inertia.js ile Vue 3 kullanır. Frontend bileşenleri [`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated) npm paketi tarafından sağlanır.

### Tailwind İçeriği

Escalated paketini Tailwind `content` yapılandırmanıza ekleyin, böylece sınıfları temizlenmez:

```js
// tailwind.config.js
content: [
    // ... your existing paths
    './node_modules/@escalated-dev/escalated/src/**/*.vue',
],
```

### Sayfa Çözümleyici

Escalated sayfalarını Inertia sayfa çözücünüze ekleyin:

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

### Tema (İsteğe Bağlı)

`EscalatedPlugin`'ı kaydedin, Escalated sayfalarını uygulamanızın düzeni içinde oluşturun — sayfa çoğaltması gerekmez:

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

Tam tema dokümantasyonu ve CSS özel özellikleri için [`@escalated-dev/escalated` README](https://github.com/escalated-dev/escalated) dosyasına bakın.

## Barındırma Modları

### Self-Hosted (varsayılan)

Her şey veritabanınızda kalır. Harici çağrı yok. Tam özerklik.

```ruby
Escalated.configure do |config|
  config.mode = :self_hosted
end
```

### Senkronize

Yerel veritabanı + birden fazla uygulama için birleşik gelen kutusu sağlayan `cloud.escalated.dev` ile otomatik senkronizasyon. Bulut erişilemezse uygulamanız çalışmaya devam eder — olaylar kuyruğa alınır ve yeniden denenir.

```ruby
Escalated.configure do |config|
  config.mode = :synced
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

### Bulut

Tüm talep verileri bulut API'sine yönlendirilir. Uygulamanız kimlik doğrulama ve UI oluşturma işlemlerini yapar, ancak depolama bulutta yaşar.

```ruby
Escalated.configure do |config|
  config.mode = :cloud
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

Her üç mod da aynı denetleyicileri, arayüzü ve iş mantığını paylaşır. Sürücü kalıbı gerisini halleder.

## Yapılandırma

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

## Zamanlama

SLA ve eskalasyon otomasyonu için bunları zamanlayıcınıza ekleyin:

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

## Rotalar

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

## Olaylar

Connect to ticket lifecycle events via ActiveSupport::Notifications:

```ruby
ActiveSupport::Notifications.subscribe("escalated.ticket_created") do |event|
  ticket = event.payload[:ticket]
  # Handle new ticket
end
```

## Gelen E-posta

Create and reply to tickets from incoming emails. Supports **Mailgun**, **Postmark**, **AWS SES** webhooks, and **IMAP** polling.

### Etkinleştir

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

### Webhook URL'leri

| Provider | URL |
|----------|-----|
| Mailgun | `POST /support/inbound/mailgun` |
| Postmark | `POST /support/inbound/postmark` |
| AWS SES | `POST /support/inbound/ses` |

### IMAP Yoklaması

Schedule `Escalated::PollImapJob` with Solid Queue, Sidekiq, or whenever:

```ruby
# config/recurring.yml (Solid Queue)
poll_imap:
  class: Escalated::PollImapJob
  schedule: every minute
```

### Özellikler

- Thread detection via subject reference and `In-Reply-To` / `References` headers
- Guest tickets for unknown senders with auto-derived display names
- Auto-reopen resolved/closed tickets on email reply
- Duplicate detection via `Message-ID` headers
- Attachment handling with configurable size and count limits
- Audit logging of every inbound email
- All settings configurable from admin panel with env fallback

## Eklenti SDK

Escalated, [Plugin SDK](https://github.com/escalated-dev/escalated-plugin-sdk) ile oluşturulan çerçeve bağımsız eklentileri destekler. Eklentiler TypeScript'te bir kez yazılır ve tüm Escalated backend'lerinde çalışır.

### Gereksinimler

- Node.js 20+
- `@escalated-dev/plugin-runtime` installed in your project

### Eklentileri Yükleme

```bash
npm install @escalated-dev/plugin-runtime
npm install @escalated-dev/plugin-slack
npm install @escalated-dev/plugin-jira
```

### SDK Eklentilerini Etkinleştirme

```ruby
# config/initializers/escalated.rb
Escalated.configure do |config|
  # ... existing config ...
  config.sdk_plugins_enabled = true
end
```

### Nasıl Çalışır

SDK plugins run as a long-lived Node.js subprocess managed by `@escalated-dev/plugin-runtime`, communicating with Rails over JSON-RPC 2.0 via stdio. The subprocess is spawned lazily on first use and automatically restarted with exponential backoff if it crashes. Every ticket lifecycle event is dual-dispatched to both Rails event handlers and the plugin runtime.

### Kendi Eklentinizi Oluşturma

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

### Kaynaklar

- [Plugin SDK](https://github.com/escalated-dev/escalated-plugin-sdk) — Eklenti oluşturmak için TypeScript SDK
- [Plugin Runtime](https://github.com/escalated-dev/escalated-plugin-runtime) — Eklentiler için çalışma zamanı sunucusu
- [Plugin Development Guide](https://github.com/escalated-dev/escalated-docs) — Tam dokümantasyon

## Diğer Platformlarda da Mevcut

- **[Escalated for Laravel](https://github.com/escalated-dev/escalated-laravel)** — Laravel Composer paketi
- **[Escalated for Rails](https://github.com/escalated-dev/escalated-rails)** — Ruby on Rails motoru (buradasınız)
- **[Escalated for Django](https://github.com/escalated-dev/escalated-django)** — Yeniden kullanılabilir Django uygulaması
- **[Escalated for AdonisJS](https://github.com/escalated-dev/escalated-adonis)** — AdonisJS v6 paketi
- **[Escalated for Filament](https://github.com/escalated-dev/escalated-filament)** — Filament v3 yönetim paneli eklentisi
- **[Shared Frontend](https://github.com/escalated-dev/escalated)** — Vue 3 + Inertia.js UI bileşenleri

Aynı mimari, aynı Vue arayüzü, aynı üç barındırma modu — tüm önemli backend çerçeveleri için.

## Testler

```bash
bundle exec rspec
```

## Lisans

MIT
