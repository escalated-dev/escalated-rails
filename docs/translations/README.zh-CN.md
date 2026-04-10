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
  <a href="README.tr.md">Türkçe</a> •
  <b>简体中文</b>
</p>

# Escalated for Rails

[![Tests](https://github.com/escalated-dev/escalated-rails/actions/workflows/run-tests.yml/badge.svg)](https://github.com/escalated-dev/escalated-rails/actions/workflows/run-tests.yml)
[![Ruby](https://img.shields.io/badge/ruby-3.1+-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/rails-7.0+-D30001?logo=rubyonrails&logoColor=white)](https://rubyonrails.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

一个功能完整、可嵌入的 Rails 支持工单系统。将其添加到任何应用中 — 即可获得完整的帮助台，包含 SLA 跟踪、升级规则、客服工作流和客户门户。无需外部服务。

> **[escalated.dev](https://escalated.dev)** — 了解更多、查看演示，并比较云端与自托管选项。

**三种托管模式。** 完全自托管运行，同步到中央云以获得多应用可见性，或将所有内容代理到云端。只需更改一个配置即可切换模式。

## 功能特性

- **工单生命周期** — 创建、分配、回复、解决、关闭、重新打开，支持可配置的状态转换
- **SLA 引擎** — 按优先级的响应和解决目标、工作时间计算、自动违规检测
- **升级规则** — 基于条件的规则，自动升级、重新排列优先级、重新分配或通知
- **客服面板** — 带过滤器、批量操作、内部备注、预设回复的工单队列
- **客户门户** — 自助工单创建、回复和状态跟踪
- **管理面板** — 管理部门、SLA 策略、升级规则、标签和查看报告
- **文件附件** — 拖拽上传，可配置存储和大小限制
- **活动时间线** — 每个工单上每个操作的完整审计日志
- **邮件通知** — 可按事件配置的通知，支持 webhook
- **部门路由** — 将客服组织到部门，支持自动分配（轮询）
- **标签系统** — 使用彩色标签分类工单
- **访客工单** — 通过访客令牌的魔法链接访问进行匿名工单提交
- **入站邮件** — 通过邮件创建和回复工单 (Mailgun, Postmark, AWS SES, IMAP)
- **Inertia.js + Vue 3 UI** — 通过 [`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated) 共享前端
- **工单拆分** — 将回复拆分为新的独立工单，同时保留原始上下文
- **Ticket snooze** — 使用预设延迟工单（1小时、4小时、明天、下周）；`rake escalated:wake_snoozed_tickets` 按计划自动唤醒
- **保存的视图 / 自定义队列** — 将过滤器预设保存、命名并共享为可重用的工单视图
- **可嵌入支持小部件** — 包含知识库搜索、工单表单和状态查询的轻量级 `<script>` 小部件
- **邮件线程** — 发送的邮件包含正确的 `In-Reply-To` 和 `References` 头部，以在邮件客户端中实现正确的线程化
- **品牌邮件模板** — 所有发送邮件的可配置 logo、主色和页脚文本
- **Real-time broadcasting** — 通过 ActionCable 进行可选广播，带有自动轮询回退
- **知识库开关** — 从管理设置中启用或禁用公共知识库

## 环境要求

- Ruby 3.1+
- Rails 7.1+
- Node.js 18+ (用于前端资源)

## 快速开始

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

## 前端设置

Escalated 使用 Inertia.js 和 Vue 3。前端组件由 npm 包 [`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated) 提供。

### Tailwind 内容

将 Escalated 包添加到 Tailwind 的 `content` 配置中，以确保其类不会被清除：

```js
// tailwind.config.js
content: [
    // ... your existing paths
    './node_modules/@escalated-dev/escalated/src/**/*.vue',
],
```

### 页面解析器

将 Escalated 页面添加到您的 Inertia 页面解析器：

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

### 主题（可选）

注册 `EscalatedPlugin` 以在您的应用布局内渲染 Escalated 页面 — 无需页面复制：

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

查看 [`@escalated-dev/escalated` README](https://github.com/escalated-dev/escalated) 以获取完整的主题文档和 CSS 自定义属性。

## 托管模式

### Self-Hosted（默认）

所有数据保留在您的数据库中。无外部调用。完全自主。

```ruby
Escalated.configure do |config|
  config.mode = :self_hosted
end
```

### 同步模式

本地数据库 + 自动同步到 `cloud.escalated.dev` 以实现跨多个应用的统一收件箱。如果云端不可达，您的应用继续工作 — 事件会排队并重试。

```ruby
Escalated.configure do |config|
  config.mode = :synced
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

### 云端

所有工单数据代理到云 API。您的应用处理认证和渲染 UI，但存储在云端。

```ruby
Escalated.configure do |config|
  config.mode = :cloud
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

三种模式共享相同的控制器、UI 和业务逻辑。驱动模式处理其余部分。

## 配置

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

## 调度

将这些添加到您的调度器以实现 SLA 和升级自动化：

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

## 路由

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

## 事件

Connect to ticket lifecycle events via ActiveSupport::Notifications:

```ruby
ActiveSupport::Notifications.subscribe("escalated.ticket_created") do |event|
  ticket = event.payload[:ticket]
  # Handle new ticket
end
```

## 入站邮件

Create and reply to tickets from incoming emails. Supports **Mailgun**, **Postmark**, **AWS SES** webhooks, and **IMAP** polling.

### 启用

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

### IMAP 轮询

Schedule `Escalated::PollImapJob` with Solid Queue, Sidekiq, or whenever:

```ruby
# config/recurring.yml (Solid Queue)
poll_imap:
  class: Escalated::PollImapJob
  schedule: every minute
```

### 功能特性

- Thread detection via subject reference and `In-Reply-To` / `References` headers
- Guest tickets for unknown senders with auto-derived display names
- Auto-reopen resolved/closed tickets on email reply
- Duplicate detection via `Message-ID` headers
- Attachment handling with configurable size and count limits
- Audit logging of every inbound email
- All settings configurable from admin panel with env fallback

## 插件 SDK

Escalated 支持使用 [Plugin SDK](https://github.com/escalated-dev/escalated-plugin-sdk) 构建的框架无关插件。插件用 TypeScript 编写一次，即可在所有 Escalated 后端上运行。

### 环境要求

- Node.js 20+
- `@escalated-dev/plugin-runtime` installed in your project

### 安装插件

```bash
npm install @escalated-dev/plugin-runtime
npm install @escalated-dev/plugin-slack
npm install @escalated-dev/plugin-jira
```

### 启用 SDK 插件

```ruby
# config/initializers/escalated.rb
Escalated.configure do |config|
  # ... existing config ...
  config.sdk_plugins_enabled = true
end
```

### 工作原理

SDK plugins run as a long-lived Node.js subprocess managed by `@escalated-dev/plugin-runtime`, communicating with Rails over JSON-RPC 2.0 via stdio. The subprocess is spawned lazily on first use and automatically restarted with exponential backoff if it crashes. Every ticket lifecycle event is dual-dispatched to both Rails event handlers and the plugin runtime.

### 构建自己的插件

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

### 资源

- [Plugin SDK](https://github.com/escalated-dev/escalated-plugin-sdk) — 用于构建插件的 TypeScript SDK
- [Plugin Runtime](https://github.com/escalated-dev/escalated-plugin-runtime) — 插件运行时宿主
- [Plugin Development Guide](https://github.com/escalated-dev/escalated-docs) — 完整文档

## 其他框架版本

- **[Escalated for Laravel](https://github.com/escalated-dev/escalated-laravel)** — Laravel Composer 包
- **[Escalated for Rails](https://github.com/escalated-dev/escalated-rails)** — Ruby on Rails 引擎（当前页面）
- **[Escalated for Django](https://github.com/escalated-dev/escalated-django)** — Django 可复用应用
- **[Escalated for AdonisJS](https://github.com/escalated-dev/escalated-adonis)** — AdonisJS v6 包
- **[Escalated for Filament](https://github.com/escalated-dev/escalated-filament)** — Filament v3 管理面板插件
- **[Shared Frontend](https://github.com/escalated-dev/escalated)** — Vue 3 + Inertia.js UI 组件

相同的架构、相同的 Vue UI、相同的三种托管模式 — 适用于每个主流后端框架。

## 测试

```bash
bundle exec rspec
```

## 许可证

MIT
