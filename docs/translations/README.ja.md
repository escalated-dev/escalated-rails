<p align="center"><sub>
  <a href="README.ar.md">العربية</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="../../README.md">English</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.it.md">Italiano</a> ·
  <b>日本語</b> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.nl.md">Nederlands</a> ·
  <a href="README.pl.md">Polski</a> ·
  <a href="README.pt-BR.md">Português (BR)</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.tr.md">Türkçe</a> ·
  <a href="README.zh-CN.md">简体中文</a>
</sub></p>

<p align="center">
  <a href="https://escalated.dev"><img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/logo.png" width="72" height="72" alt="Escalated"></a>
</p>

<h1 align="center">Escalated for Rails</h1>

<p align="center">
  Rails アプリに本格的なヘルプデスクを追加します。<br>
  チケット、SLA、エスカレーションルール、エージェント用受信トレイ、カスタマーポータルが、あなた自身のデータベース上で動きます。
</p>

<p align="center">
  <a href="https://escalated.dev"><b>ウェブサイト</b></a> ·
  <a href="https://escalated.dev/docs"><b>ドキュメント</b></a> ·
  <a href="https://escalated.dev/cloud"><b>Cloud</b></a> ·
  <a href="../../CHANGELOG.md"><b>変更履歴</b></a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-dark.png">
  <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-light.png" alt="Escalated のエージェント用受信トレイ: 件数付きの保存ビュー、各チケットの SLA カウントダウンと優先度" width="100%">
</picture>

## できること

<table>
  <tr>
    <td width="40%">
      <h3>エージェントが一日中使える受信トレイ</h3>
      会話、内部メモ、定型返信、SLA タイマーをひとつの画面で扱えます。チケットは Mailgun、Postmark、SES、IMAP 経由のメールでも届きます。
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-light.png" alt="返信エディタ付きのエージェント作業画面で開いたチケット">
      </picture>
    </td>
  </tr>
  <tr>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-light.png" alt="応答時間、CSAT、SLA 違反を表示する管理者用レポートページ">
      </picture>
    </td>
    <td width="40%">
      <h3>状況が見える SLA とエスカレーションルール</h3>
      営業時間を考慮した優先度ごとの応答・解決目標、目標を外れたときにエスカレーションや再割り当てを行うルール、違反に関するレポートを備えています。
    </td>
  </tr>
  <tr>
    <td width="40%">
      <h3>最初から用意されたカスタマーポータル</h3>
      顧客はあなたのアプリ内でチケットの作成、返信、ステータス確認ができます。script タグひとつで他のサイトにウィジェットを埋め込めます。
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/portal-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/portal-light.png" alt="カスタマーポータルのチケット一覧">
      </picture>
    </td>
  </tr>
</table>

## 機能

<table>
<tr>
<td width="33%" valign="top">

**チケットと受信トレイ**
- ステータス遷移を含むライフサイクル全体
- キューのフィルタと一括操作
- 内部メモと定型返信
- 返信を新しいチケットに分割
- プリセット付きスヌーズと自動復帰
- 保存ビューと共有キュー

</td>
<td width="33%" valign="top">

**SLA とエスカレーション**
- 優先度ごとの応答・解決目標
- 営業時間と違反の検出
- エスカレーション、再割り当て、通知を行うルール
- ラウンドロビンによる部署ルーティング

</td>
<td width="33%" valign="top">

**顧客**
- セルフサービスのカスタマーポータル
- マジックリンクでアクセスできるゲストチケット
- ナレッジベース検索付きの埋め込みウィジェット
- オフにできる公開ナレッジベース

</td>
</tr>
<tr>
<td width="33%" valign="top">

**メール**
- Mailgun、Postmark、SES、IMAP 経由の受信
- メールクライアントでスレッド表示される返信
- ブランドに合わせたメールテンプレート
- イベントごとの通知と Webhook

</td>
<td width="33%" valign="top">

**管理とアクセス**
- 部署、SLA、ルール、タグ、レポート
- 自前の管理画面への埋め込み (任意)
- インストール時に切り替えられるロールと権限
- 全チケットのアクティビティタイムライン

</td>
<td width="33%" valign="top">

**内部の仕組み**
- Vue 3 と Inertia.js による共通 UI
- ストレージとサイズ制限付きのアップロード
- チケットを整理する色付きタグ
- ActionCable によるリアルタイム更新とポーリングへのフォールバック

</td>
</tr>
</table>

<p align="center"><sub><a href="../features.md">すべての機能の詳細</a></sub></p>

<p align="center"><b>使用技術</b></p>

<p align="center">
  <a href="https://rubyonrails.org"><img src="https://img.shields.io/badge/Ruby%20on%20Rails-D30001?style=for-the-badge&logo=rubyonrails&logoColor=white" alt="Ruby on Rails"></a>
  <a href="https://www.ruby-lang.org"><img src="https://img.shields.io/badge/Ruby-CC342D?style=for-the-badge&logo=ruby&logoColor=white" alt="Ruby"></a>
  <a href="https://vuejs.org"><img src="https://img.shields.io/badge/Vue.js-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white" alt="Vue.js"></a>
  <a href="https://inertiajs.com"><img src="https://img.shields.io/badge/Inertia-9553E9?style=for-the-badge&logo=inertia&logoColor=white" alt="Inertia"></a>
</p>

## クイックスタート

```bash
bundle add escalated
npm install @escalated-dev/escalated
rails generate escalated:install
rails db:migrate
```

その後 `/support` を開いてください。Ruby 3.1 以上と Rails 7.1 以上が必要です。`Ticketable` concern とアクセスチェックについては[スタートガイド](../getting-started.md)で説明しています。

## さらに詳しく

- [全機能](../features.md) · [はじめに](../getting-started.md) · [フロントエンド統合](../frontend-integration.md)
- [設定、ホスティングモード、イベント、ルート](../operations.md) · [名前付きルート](../named-routes.md)
- [エージェントパネル](../agent-panel.md) · [アクセス制御](../access-control.md) · [チケットのアクセスとルーティング](../ticket-access-and-routing.md)
- [受信メール](../inbound-email.md) · [ウィジェットの埋め込み](../embedding-the-widget.md) · [管理画面の埋め込み](../embedding-admin.md)
- [ゲストアクセス](../guest-access.md) · [非公開の添付ファイル](../private-attachments.md)
- [Plugin SDK](../plugin-sdk.md) · [プラグイン](../plugins.md) · [ニュースレター](../newsletters.md)

Escalated は [Laravel](https://github.com/escalated-dev/escalated-laravel)、[Django](https://github.com/escalated-dev/escalated-django)、[NestJS](https://github.com/escalated-dev/escalated-nestjs)、[AdonisJS](https://github.com/escalated-dev/escalated-adonis)、[Symfony](https://github.com/escalated-dev/escalated-symfony)、[Phoenix](https://github.com/escalated-dev/escalated-phoenix)、[Go](https://github.com/escalated-dev/escalated-go)、[.NET](https://github.com/escalated-dev/escalated-dotnet)、[Spring](https://github.com/escalated-dev/escalated-spring)、[WordPress](https://github.com/escalated-dev/escalated-wordpress)、[Filament](https://github.com/escalated-dev/escalated-filament) 向けにも提供されています。UI は [escalated](https://github.com/escalated-dev/escalated) にあります。

## ライセンス

MIT. Copyright (c) 2026 Escalated.dev. [LICENSE](../../LICENSE) を参照してください。
