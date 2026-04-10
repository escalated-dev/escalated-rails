<p align="center">
  <a href="README.ar.md">العربية</a> •
  <a href="README.de.md">Deutsch</a> •
  <a href="../../README.md">English</a> •
  <a href="README.es.md">Español</a> •
  <a href="README.fr.md">Français</a> •
  <a href="README.it.md">Italiano</a> •
  <b>日本語</b> •
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

Rails用のフル機能で埋め込み可能なサポートチケットシステム。任意のアプリに導入するだけで、SLA追跡、エスカレーションルール、エージェントワークフロー、カスタマーポータルを備えた完全なヘルプデスクが手に入ります。外部サービスは不要です。

> **[escalated.dev](https://escalated.dev)** — 詳細の確認、デモの閲覧、クラウドとセルフホストのオプション比較はこちら。

**3つのホスティングモード。** 完全セルフホスト、マルチアプリの可視性のためのセントラルクラウドへの同期、またはすべてをクラウドにプロキシ。設定を1つ変更するだけでモードを切り替えられます。

## 機能

- **チケットのライフサイクル** — 設定可能なステータス遷移による作成、割り当て、返信、解決、クローズ、再オープン
- **SLAエンジン** — 優先度別の応答・解決目標、営業時間計算、自動違反検出
- **エスカレーションルール** — 自動的にエスカレート、優先度変更、再割り当て、通知する条件ベースのルール
- **エージェントダッシュボード** — フィルター、一括操作、内部メモ、定型応答付きのチケットキュー
- **カスタマーポータル** — セルフサービスのチケット作成、返信、ステータス追跡
- **管理パネル** — 部門、SLAポリシー、エスカレーションルール、タグの管理とレポートの表示
- **ファイル添付** — ドラッグ＆ドロップアップロード、設定可能なストレージとサイズ制限
- **アクティビティタイムライン** — すべてのチケットのすべてのアクションの完全な監査ログ
- **メール通知** — Webhookサポート付きの設定可能なイベント単位の通知
- **部門ルーティング** — エージェントを部門に整理し、自動割り当て（ラウンドロビン）
- **タグ付けシステム** — 色付きタグでチケットを分類
- **ゲストチケット** — ゲストトークンによるマジックリンクアクセス付きの匿名チケット送信
- **受信メール** — メールでチケットの作成と返信 (Mailgun, Postmark, AWS SES, IMAP)
- **Inertia.js + Vue 3 UI** — [`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated) による共有フロントエンド
- **チケットの分割** — 元のコンテキストを保持しながら返信を新しい独立チケットに分割
- **Ticket snooze** — プリセットでチケットをスヌーズ（1時間、4時間、明日、来週）、`rake escalated:wake_snoozed_tickets` がスケジュールに従って自動的に起動
- **保存済みビュー / カスタムキュー** — フィルタープリセットを再利用可能なチケットビューとして保存、命名、共有
- **埋め込み可能なサポートウィジェット** — KB検索、チケットフォーム、ステータス確認付きの軽量`<script>`ウィジェット
- **メールスレッディング** — 送信メールに適切な`In-Reply-To`および`References`ヘッダーを含め、メールクライアントでの正しいスレッディングを実現
- **ブランドメールテンプレート** — すべての送信メールのロゴ、プライマリカラー、フッターテキストを設定可能
- **Real-time broadcasting** — ActionCableによるオプトインブロードキャスト、自動ポーリングフォールバック付き
- **ナレッジベースの切り替え** — 管理設定から公開ナレッジベースを有効/無効に切り替え

## 要件

- Ruby 3.1+
- Rails 7.1+
- Node.js 18+ (フロントエンドアセット用)

## クイックスタート

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

## フロントエンドのセットアップ

EscalatedはInertia.jsとVue 3を使用します。フロントエンドコンポーネントはnpmパッケージ[`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated)で提供されます。

### Tailwindコンテンツ

EscalatedパッケージをTailwindの`content`設定に追加して、そのクラスがパージされないようにします：

```js
// tailwind.config.js
content: [
    // ... your existing paths
    './node_modules/@escalated-dev/escalated/src/**/*.vue',
],
```

### ページリゾルバー

EscalatedのページをInertiaページリゾルバーに追加します：

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

### テーマ設定（オプション）

`EscalatedPlugin`を登録して、アプリのレイアウト内でEscalatedページをレンダリングします — ページの複製は不要です：

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

テーマの完全なドキュメントとCSSカスタムプロパティについては[`@escalated-dev/escalated` README](https://github.com/escalated-dev/escalated)を参照してください。

## ホスティングモード

### Self-Hosted（デフォルト）

すべてがデータベースに保存されます。外部呼び出しなし。完全な自律性。

```ruby
Escalated.configure do |config|
  config.mode = :self_hosted
end
```

### 同期モード

ローカルデータベース + `cloud.escalated.dev`への自動同期で複数アプリにわたる統合受信箱。クラウドに到達できない場合、アプリは動作を継続します — イベントはキューに入り、リトライされます。

```ruby
Escalated.configure do |config|
  config.mode = :synced
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

### クラウド

すべてのチケットデータはクラウドAPIにプロキシされます。アプリが認証とUIのレンダリングを処理しますが、ストレージはクラウドにあります。

```ruby
Escalated.configure do |config|
  config.mode = :cloud
  config.hosted_api_url = "https://cloud.escalated.dev/api/v1"
  config.hosted_api_key = ENV["ESCALATED_API_KEY"]
end
```

3つのモードすべてが同じコントローラー、UI、ビジネスロジックを共有します。ドライバーパターンが残りを処理します。

## 設定

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

## スケジューリング

SLAとエスカレーションの自動化のためにスケジューラーに追加してください：

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

## ルート

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

## イベント

Connect to ticket lifecycle events via ActiveSupport::Notifications:

```ruby
ActiveSupport::Notifications.subscribe("escalated.ticket_created") do |event|
  ticket = event.payload[:ticket]
  # Handle new ticket
end
```

## 受信メール

Create and reply to tickets from incoming emails. Supports **Mailgun**, **Postmark**, **AWS SES** webhooks, and **IMAP** polling.

### 有効化

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

### IMAPポーリング

Schedule `Escalated::PollImapJob` with Solid Queue, Sidekiq, or whenever:

```ruby
# config/recurring.yml (Solid Queue)
poll_imap:
  class: Escalated::PollImapJob
  schedule: every minute
```

### 機能

- Thread detection via subject reference and `In-Reply-To` / `References` headers
- Guest tickets for unknown senders with auto-derived display names
- Auto-reopen resolved/closed tickets on email reply
- Duplicate detection via `Message-ID` headers
- Attachment handling with configurable size and count limits
- Audit logging of every inbound email
- All settings configurable from admin panel with env fallback

## プラグインSDK

Escalatedは[Plugin SDK](https://github.com/escalated-dev/escalated-plugin-sdk)で構築されたフレームワーク非依存のプラグインをサポートしています。プラグインはTypeScriptで一度書くだけで、すべてのEscalatedバックエンドで動作します。

### 要件

- Node.js 20+
- `@escalated-dev/plugin-runtime` installed in your project

### プラグインのインストール

```bash
npm install @escalated-dev/plugin-runtime
npm install @escalated-dev/plugin-slack
npm install @escalated-dev/plugin-jira
```

### SDKプラグインの有効化

```ruby
# config/initializers/escalated.rb
Escalated.configure do |config|
  # ... existing config ...
  config.sdk_plugins_enabled = true
end
```

### 仕組み

SDK plugins run as a long-lived Node.js subprocess managed by `@escalated-dev/plugin-runtime`, communicating with Rails over JSON-RPC 2.0 via stdio. The subprocess is spawned lazily on first use and automatically restarted with exponential backoff if it crashes. Every ticket lifecycle event is dual-dispatched to both Rails event handlers and the plugin runtime.

### 独自プラグインの作成

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

### リソース

- [Plugin SDK](https://github.com/escalated-dev/escalated-plugin-sdk) — プラグイン構築用TypeScript SDK
- [Plugin Runtime](https://github.com/escalated-dev/escalated-plugin-runtime) — プラグイン用ランタイムホスト
- [Plugin Development Guide](https://github.com/escalated-dev/escalated-docs) — 完全なドキュメント

## 他のフレームワーク向けも提供

- **[Escalated for Laravel](https://github.com/escalated-dev/escalated-laravel)** — Laravel Composerパッケージ
- **[Escalated for Rails](https://github.com/escalated-dev/escalated-rails)** — Ruby on Railsエンジン（現在のページ）
- **[Escalated for Django](https://github.com/escalated-dev/escalated-django)** — Django再利用可能アプリ
- **[Escalated for AdonisJS](https://github.com/escalated-dev/escalated-adonis)** — AdonisJS v6パッケージ
- **[Escalated for Filament](https://github.com/escalated-dev/escalated-filament)** — Filament v3管理パネルプラグイン
- **[Shared Frontend](https://github.com/escalated-dev/escalated)** — Vue 3 + Inertia.js UIコンポーネント

同じアーキテクチャ、同じVue UI、同じ3つのホスティングモード — すべての主要バックエンドフレームワークに対応。

## テスト

```bash
bundle exec rspec
```

## ライセンス

MIT
