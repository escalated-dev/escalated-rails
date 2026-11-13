<p align="center"><sub>
  <a href="README.ar.md">العربية</a> ·
  <b>Deutsch</b> ·
  <a href="../../README.md">English</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.it.md">Italiano</a> ·
  <a href="README.ja.md">日本語</a> ·
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
  Füge deiner Rails-App einen vollständigen Helpdesk hinzu.<br>
  Tickets, SLAs, Eskalationsregeln, ein Agenten-Posteingang und ein Kundenportal, direkt auf deiner eigenen Datenbank.
</p>

<p align="center">
  <a href="https://escalated.dev"><b>Website</b></a> ·
  <a href="https://escalated.dev/docs"><b>Dokumentation</b></a> ·
  <a href="https://escalated.dev/cloud"><b>Cloud</b></a> ·
  <a href="../../CHANGELOG.md"><b>Änderungsprotokoll</b></a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-dark.png">
  <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-light.png" alt="Der Agenten-Posteingang von Escalated: gespeicherte Ansichten mit Zählern, SLA-Countdowns und Prioritäten an jedem Ticket" width="100%">
</picture>

## Was es kann

<table>
  <tr>
    <td width="40%">
      <h3>Ein Posteingang, in dem deine Agenten den ganzen Tag arbeiten können</h3>
      Konversation, interne Notizen, Textbausteine und SLA-Timer auf einem Bildschirm. Tickets kommen auch per E-Mail über Mailgun, Postmark, SES oder IMAP an.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-light.png" alt="Ein geöffnetes Ticket im Agenten-Arbeitsbereich mit dem Antwort-Editor">
      </picture>
    </td>
  </tr>
  <tr>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-light.png" alt="Die Berichtsseite im Adminbereich mit Antwortzeiten, CSAT und SLA-Verstößen">
      </picture>
    </td>
    <td width="40%">
      <h3>SLAs und Eskalationsregeln, die du im Blick hast</h3>
      Reaktions- und Lösungsziele pro Priorität mit Geschäftszeiten, Regeln, die eskalieren oder neu zuweisen, wenn ein Ziel verfehlt wird, und Berichte über Verstöße.
    </td>
  </tr>
  <tr>
    <td width="40%">
      <h3>Ein Kundenportal, das schon fertig ist</h3>
      Kunden eröffnen Tickets, antworten und prüfen den Status direkt in deiner App. Mit einem einzigen Script-Tag bettest du das Widget auf anderen Websites ein.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/portal-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/portal-light.png" alt="Die Ticketliste im Kundenportal">
      </picture>
    </td>
  </tr>
</table>

## Funktionen

<table>
<tr>
<td width="33%" valign="top">

**Tickets und Posteingang**
- Vollständiger Lebenszyklus mit Statusübergängen
- Queue-Filter und Massenaktionen
- Interne Notizen und Textbausteine
- Eine Antwort in ein neues Ticket abspalten
- Zurückstellen mit Vorlagen und automatischem Wiederaufleben
- Gespeicherte Ansichten und geteilte Queues

</td>
<td width="33%" valign="top">

**SLAs und Eskalation**
- Reaktions- und Lösungsziele pro Priorität
- Geschäftszeiten und Erkennung von Verstößen
- Regeln, die eskalieren, neu zuweisen oder benachrichtigen
- Abteilungs-Routing mit Round-Robin

</td>
<td width="33%" valign="top">

**Kunden**
- Self-Service-Kundenportal
- Gast-Tickets mit Zugang per Magic Link
- Einbettbares Widget mit Wissensdatenbank-Suche
- Öffentliche Wissensdatenbank, die du abschalten kannst

</td>
</tr>
<tr>
<td width="33%" valign="top">

**E-Mail**
- Eingang über Mailgun, Postmark, SES oder IMAP
- Antworten als Threads in Mail-Clients
- E-Mail-Vorlagen in deinem Branding
- Benachrichtigungen und Webhooks pro Event

</td>
<td width="33%" valign="top">

**Administration und Zugriff**
- Abteilungen, SLAs, Regeln, Tags und Berichte
- Optional in deinen eigenen Adminbereich eingebettet
- Rollen und Berechtigungen als Installationsschalter
- Aktivitätsverlauf an jedem Ticket

</td>
<td width="33%" valign="top">

**Unter der Haube**
- Gemeinsame Oberfläche mit Vue 3 und Inertia.js
- Uploads mit Speicher- und Größenlimits
- Farbige Tags zum Sortieren von Tickets
- Echtzeit über ActionCable mit Polling als Fallback

</td>
</tr>
</table>

<p align="center"><sub><a href="../features.md">Alle Funktionen im Detail</a></sub></p>

<p align="center"><b>Entwickelt mit</b></p>

<p align="center">
  <a href="https://rubyonrails.org"><img src="https://img.shields.io/badge/Ruby%20on%20Rails-D30001?style=for-the-badge&logo=rubyonrails&logoColor=white" alt="Ruby on Rails"></a>
  <a href="https://www.ruby-lang.org"><img src="https://img.shields.io/badge/Ruby-CC342D?style=for-the-badge&logo=ruby&logoColor=white" alt="Ruby"></a>
  <a href="https://vuejs.org"><img src="https://img.shields.io/badge/Vue.js-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white" alt="Vue.js"></a>
  <a href="https://inertiajs.com"><img src="https://img.shields.io/badge/Inertia-9553E9?style=for-the-badge&logo=inertia&logoColor=white" alt="Inertia"></a>
</p>

## Schnellstart

```bash
bundle add escalated
npm install @escalated-dev/escalated
rails generate escalated:install
rails db:migrate
```

Rufe danach `/support` auf. Voraussetzungen: Ruby 3.1+ und Rails 7.1+. Die [Einstiegsanleitung](../getting-started.md) erklärt das `Ticketable`-Concern und die Zugriffsprüfungen.

## Mehr erfahren

- [Alle Funktionen](../features.md) · [Erste Schritte](../getting-started.md) · [Frontend-Integration](../frontend-integration.md)
- [Konfiguration, Hosting-Modi, Events und Routen](../operations.md) · [Benannte Routen](../named-routes.md)
- [Agenten-Panel](../agent-panel.md) · [Zugriffskontrolle](../access-control.md) · [Ticketzugriff und Routing](../ticket-access-and-routing.md)
- [Eingehende E-Mails](../inbound-email.md) · [Widget einbetten](../embedding-the-widget.md) · [Adminbereich einbetten](../embedding-admin.md)
- [Gastzugang](../guest-access.md) · [Private Anhänge](../private-attachments.md)
- [Plugin SDK](../plugin-sdk.md) · [Plugins](../plugins.md) · [Newsletter](../newsletters.md)

Escalated gibt es auch für [Laravel](https://github.com/escalated-dev/escalated-laravel), [Django](https://github.com/escalated-dev/escalated-django), [NestJS](https://github.com/escalated-dev/escalated-nestjs), [AdonisJS](https://github.com/escalated-dev/escalated-adonis), [Symfony](https://github.com/escalated-dev/escalated-symfony), [Phoenix](https://github.com/escalated-dev/escalated-phoenix), [Go](https://github.com/escalated-dev/escalated-go), [.NET](https://github.com/escalated-dev/escalated-dotnet), [Spring](https://github.com/escalated-dev/escalated-spring), [WordPress](https://github.com/escalated-dev/escalated-wordpress) und [Filament](https://github.com/escalated-dev/escalated-filament). Die Oberfläche liegt in [escalated](https://github.com/escalated-dev/escalated).

## Lizenz

MIT. Copyright (c) 2026 Escalated.dev. Siehe [LICENSE](../../LICENSE).
