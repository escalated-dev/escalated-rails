<p align="center">
  <a href="README.ar.md">العربية</a> •
  <a href="README.de.md">Deutsch</a> •
  <a href="../../README.md">English</a> •
  <a href="README.es.md">Español</a> •
  <a href="README.fr.md">Français</a> •
  <a href="README.it.md">Italiano</a> •
  <a href="README.ja.md">日本語</a> •
  <b>한국어</b> •
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

Rails용 완전한 기능을 갖춘 임베드 가능한 지원 티켓 시스템입니다. 어떤 앱에든 추가하면 SLA 추적, 에스컬레이션 규칙, 상담원 워크플로우, 고객 포털을 갖춘 완전한 헬프데스크를 얻을 수 있습니다. 외부 서비스가 필요 없습니다.

> **[escalated.dev](https://escalated.dev)** — 자세히 알아보고, 데모를 보고, 클라우드와 셀프호스팅 옵션을 비교하세요.

**세 가지 호스팅 모드.** 완전한 셀프호스팅, 멀티앱 가시성을 위한 중앙 클라우드 동기화, 또는 모든 것을 클라우드로 프록시. 설정 하나만 변경하면 모드를 전환할 수 있습니다.

## 기능

- **티켓 라이프사이클** — 구성 가능한 상태 전환으로 생성, 할당, 답변, 해결, 닫기, 재개
- **SLA 엔진** — 우선순위별 응답 및 해결 목표, 업무 시간 계산, 자동 위반 감지
- **에스컬레이션 규칙** — 자동으로 에스컬레이트, 우선순위 변경, 재할당 또는 알림하는 조건 기반 규칙
- **에이전트 대시보드** — 필터, 대량 작업, 내부 메모, 정형 응답이 포함된 티켓 큐
- **고객 포털** — 셀프서비스 티켓 생성, 답변, 상태 추적
- **관리자 패널** — 부서, SLA 정책, 에스컬레이션 규칙, 태그 관리 및 보고서 보기
- **파일 첨부** — 드래그 앤 드롭 업로드, 구성 가능한 스토리지 및 크기 제한
- **활동 타임라인** — 모든 티켓의 모든 작업에 대한 전체 감사 로그
- **이메일 알림** — 웹훅 지원을 포함한 이벤트별 구성 가능한 알림
- **부서 라우팅** — 에이전트를 부서별로 조직하고 자동 할당 (라운드 로빈)
- **태그 시스템** — 색상 태그로 티켓 분류
- **게스트 티켓** — 게스트 토큰을 통한 매직 링크 접근으로 익명 티켓 제출
- **수신 이메일** — 이메일로 티켓 생성 및 답변 (Mailgun, Postmark, AWS SES, IMAP)
- **Inertia.js + Vue 3 UI** — [`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated)를 통한 공유 프론트엔드
- **티켓 분할** — 원래 컨텍스트를 보존하면서 답변을 새로운 독립 티켓으로 분할
- **Ticket snooze** — 프리셋으로 티켓 스누즈 (1시간, 4시간, 내일, 다음 주); `rake escalated:wake_snoozed_tickets`가 예정대로 자동으로 깨움
- **저장된 뷰 / 커스텀 큐** — 필터 프리셋을 재사용 가능한 티켓 뷰로 저장, 명명 및 공유
- **임베드 가능한 지원 위젯** — KB 검색, 티켓 폼, 상태 확인이 포함된 경량 `<script>` 위젯
- **이메일 스레딩** — 발신 이메일에 적절한 `In-Reply-To` 및 `References` 헤더를 포함하여 메일 클라이언트에서 올바른 스레딩 지원
- **브랜드 이메일 템플릿** — 모든 발신 이메일에 대해 로고, 기본 색상, 바닥글 텍스트 구성 가능
- **Real-time broadcasting** — ActionCable을 통한 선택적 브로드캐스팅, 자동 폴링 폴백 포함
- **지식 베이스 토글** — 관리자 설정에서 공개 지식 베이스 활성화 또는 비활성화

## 요구 사항

- Ruby 3.1+
- Rails 7.1+
- Node.js 18+ (프론트엔드 자산용)

## 빠른 시작

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

## 프론트엔드 설정

Escalated는 Inertia.js와 Vue 3를 사용합니다. 프론트엔드 컴포넌트는 npm 패키지 [`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated)에서 제공됩니다.

### Tailwind 콘텐츠

Escalated 패키지를 Tailwind `content` 설정에 추가하여 클래스가 제거되지 않도록 하세요:

```js
// tailwind.config.js
content: [
    // ... your existing paths
    './node_modules/@escalated-dev/escalated/src/**/*.vue',
],
```

### 페이지 리졸버

Escalated 페이지를 Inertia 페이지 리줄버에 추가하세요:

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

### 테마 설정 (선택사항)

`EscalatedPlugin`을 등록하여 앱의 레이아웃 내에서 Escalated 페이지를 렌더링하세요 — 페이지 복제가 필요 없습니다:

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

전체 테마 문서와 CSS 커스텀 속성에 대해서는 [`@escalated-dev/escalated` README](https://github.com/escalated-dev/escalated)를 참조하세요.

## 호스팅 모드

### Self-Hosted (기본값)

모든 것이 데이터베이스에 유지됩니다. 외부 호출 없음. 완전한 자율성.

```ruby
Escalated.configure do |config|
  config.mode = :self_hosted
end
```

### 동기화

로컬 데이터베이스 + `cloud.escalated.dev`로의 자동 동기화로 여러 앱에 걸친 통합 수신함. 클라우드에 연결할 수 없는 경우 앱은 계속 작동합니다 — 이벤트가 대기열에 추가되고 재시도됩니다.

```ruby
Escalated.configure do |config|
  config.mode = :synced
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

### 클라우드

모든 티켓 데이터가 클라우드 API로 프록시됩니다. 앱이 인증과 UI 렌더링을 처리하지만 저장소는 클라우드에 있습니다.

```ruby
Escalated.configure do |config|
  config.mode = :cloud
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

세 가지 모드 모두 동일한 컨트롤러, UI 및 비즈니스 로직을 공유합니다. 드라이버 패턴이 나머지를 처리합니다.

## 설정

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

## 스케줄링

SLA 및 에스컬레이션 자동화를 위해 스케줄러에 추가하세요:

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

## 라우트

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

## 이벤트

Connect to ticket lifecycle events via ActiveSupport::Notifications:

```ruby
ActiveSupport::Notifications.subscribe("escalated.ticket_created") do |event|
  ticket = event.payload[:ticket]
  # Handle new ticket
end
```

## 수신 이메일

Create and reply to tickets from incoming emails. Supports **Mailgun**, **Postmark**, **AWS SES** webhooks, and **IMAP** polling.

### 활성화

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

### Webhook URL

| Provider | URL |
|----------|-----|
| Mailgun | `POST /support/inbound/mailgun` |
| Postmark | `POST /support/inbound/postmark` |
| AWS SES | `POST /support/inbound/ses` |

### IMAP 폴링

Schedule `Escalated::PollImapJob` with Solid Queue, Sidekiq, or whenever:

```ruby
# config/recurring.yml (Solid Queue)
poll_imap:
  class: Escalated::PollImapJob
  schedule: every minute
```

### 기능

- Thread detection via subject reference and `In-Reply-To` / `References` headers
- Guest tickets for unknown senders with auto-derived display names
- Auto-reopen resolved/closed tickets on email reply
- Duplicate detection via `Message-ID` headers
- Attachment handling with configurable size and count limits
- Audit logging of every inbound email
- All settings configurable from admin panel with env fallback

## 플러그인 SDK

Escalated는 [Plugin SDK](https://github.com/escalated-dev/escalated-plugin-sdk)로 구축된 프레임워크 독립적인 플러그인을 지원합니다. 플러그인은 TypeScript로 한 번 작성하면 모든 Escalated 백엔드에서 작동합니다.

### 요구 사항

- Node.js 20+
- `@escalated-dev/plugin-runtime` installed in your project

### 플러그인 설치

```bash
npm install @escalated-dev/plugin-runtime
npm install @escalated-dev/plugin-slack
npm install @escalated-dev/plugin-jira
```

### SDK 플러그인 활성화

```ruby
# config/initializers/escalated.rb
Escalated.configure do |config|
  # ... existing config ...
  config.sdk_plugins_enabled = true
end
```

### 작동 방식

SDK plugins run as a long-lived Node.js subprocess managed by `@escalated-dev/plugin-runtime`, communicating with Rails over JSON-RPC 2.0 via stdio. The subprocess is spawned lazily on first use and automatically restarted with exponential backoff if it crashes. Every ticket lifecycle event is dual-dispatched to both Rails event handlers and the plugin runtime.

### 자체 플러그인 만들기

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

### 리소스

- [Plugin SDK](https://github.com/escalated-dev/escalated-plugin-sdk) — 플러그인 구축을 위한 TypeScript SDK
- [Plugin Runtime](https://github.com/escalated-dev/escalated-plugin-runtime) — 플러그인용 런타임 호스트
- [Plugin Development Guide](https://github.com/escalated-dev/escalated-docs) — 전체 문서

## 다른 프레임워크에서도 이용 가능

- **[Escalated for Laravel](https://github.com/escalated-dev/escalated-laravel)** — Laravel Composer 패키지
- **[Escalated for Rails](https://github.com/escalated-dev/escalated-rails)** — Ruby on Rails 엔진 (현재 페이지)
- **[Escalated for Django](https://github.com/escalated-dev/escalated-django)** — Django 재사용 앱
- **[Escalated for AdonisJS](https://github.com/escalated-dev/escalated-adonis)** — AdonisJS v6 패키지
- **[Escalated for Filament](https://github.com/escalated-dev/escalated-filament)** — Filament v3 관리 패널 플러그인
- **[Shared Frontend](https://github.com/escalated-dev/escalated)** — Vue 3 + Inertia.js UI 컴포넌트

동일한 아키텍처, 동일한 Vue UI, 동일한 세 가지 호스팅 모드 — 모든 주요 백엔드 프레임워크에 대응.

## 테스트

```bash
bundle exec rspec
```

## 라이선스

MIT
