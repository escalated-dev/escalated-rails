<p align="center"><sub>
  <a href="README.ar.md">العربية</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="../../README.md">English</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.it.md">Italiano</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <b>Nederlands</b> ·
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
  Voeg een complete helpdesk toe aan je Rails-app.<br>
  Tickets, SLA's, escalatieregels, een inbox voor agents en een klantportaal, gewoon op je eigen database.
</p>

<p align="center">
  <a href="https://escalated.dev"><b>Website</b></a> ·
  <a href="https://escalated.dev/docs"><b>Documentatie</b></a> ·
  <a href="https://escalated.dev/cloud"><b>Cloud</b></a> ·
  <a href="../../CHANGELOG.md"><b>Wijzigingslog</b></a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-dark.png">
  <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-light.png" alt="De agent-inbox van Escalated: opgeslagen weergaven met tellers, SLA-afteltimers en prioriteiten op elk ticket" width="100%">
</picture>

## Wat het doet

<table>
  <tr>
    <td width="40%">
      <h3>Een inbox waarin je agents de hele dag kunnen werken</h3>
      Gesprek, interne notities, standaardantwoorden en SLA-timers op één scherm. Tickets komen ook per e-mail binnen via Mailgun, Postmark, SES of IMAP.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-light.png" alt="Een geopend ticket in de agent-werkruimte met de antwoordeditor">
      </picture>
    </td>
  </tr>
  <tr>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-light.png" alt="De rapportagepagina in het beheer met reactietijden, CSAT en SLA-overschrijdingen">
      </picture>
    </td>
    <td width="40%">
      <h3>SLA's en escalatieregels die je kunt zien</h3>
      Reactie- en oplosdoelen per prioriteit met kantooruren, regels die escaleren of opnieuw toewijzen als een doel niet wordt gehaald, en rapporten over overschrijdingen.
    </td>
  </tr>
  <tr>
    <td width="40%">
      <h3>Een klantportaal dat al klaar is</h3>
      Klanten openen tickets, reageren en bekijken de status in je eigen app. Met één scripttag plaats je de widget op andere websites.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/portal-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/portal-light.png" alt="De ticketlijst in het klantportaal">
      </picture>
    </td>
  </tr>
</table>

## Functies

<table>
<tr>
<td width="33%" valign="top">

**Tickets en inbox**
- Volledige levenscyclus met statusovergangen
- Wachtrijfilters en bulkacties
- Interne notities en standaardantwoorden
- Een antwoord afsplitsen naar een nieuw ticket
- Snoozen met voorinstellingen en automatisch wekken
- Opgeslagen weergaven en gedeelde wachtrijen

</td>
<td width="33%" valign="top">

**SLA's en escalatie**
- Reactie- en oplosdoelen per prioriteit
- Kantooruren en detectie van overschrijdingen
- Regels die escaleren, opnieuw toewijzen of melden
- Routering per afdeling met round-robin

</td>
<td width="33%" valign="top">

**Klanten**
- Selfservice-klantportaal
- Gasttickets met toegang via magic link
- Insluitbare widget met zoeken in de kennisbank
- Openbare kennisbank die je kunt uitschakelen

</td>
</tr>
<tr>
<td width="33%" valign="top">

**E-mail**
- Inkomend via Mailgun, Postmark, SES of IMAP
- Antwoorden als thread in mailclients
- E-mailsjablonen in je eigen huisstijl
- Meldingen en webhooks per gebeurtenis

</td>
<td width="33%" valign="top">

**Beheer en toegang**
- Afdelingen, SLA's, regels, tags en rapporten
- Optioneel ingebed in je eigen beheeromgeving
- Rollen en rechten als schakelaar bij installatie
- Activiteitentijdlijn op elk ticket

</td>
<td width="33%" valign="top">

**Onder de motorkap**
- Gedeelde UI met Vue 3 en Inertia.js
- Uploads met opslag- en groottelimieten
- Gekleurde tags om tickets te sorteren
- Realtime via ActionCable met polling als terugval

</td>
</tr>
</table>

<p align="center"><sub><a href="../features.md">Alle functies in detail</a></sub></p>

<p align="center"><b>Gebouwd met</b></p>

<p align="center">
  <a href="https://rubyonrails.org"><img src="https://img.shields.io/badge/Ruby%20on%20Rails-D30001?style=for-the-badge&logo=rubyonrails&logoColor=white" alt="Ruby on Rails"></a>
  <a href="https://www.ruby-lang.org"><img src="https://img.shields.io/badge/Ruby-CC342D?style=for-the-badge&logo=ruby&logoColor=white" alt="Ruby"></a>
  <a href="https://vuejs.org"><img src="https://img.shields.io/badge/Vue.js-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white" alt="Vue.js"></a>
  <a href="https://inertiajs.com"><img src="https://img.shields.io/badge/Inertia-9553E9?style=for-the-badge&logo=inertia&logoColor=white" alt="Inertia"></a>
</p>

## Snel aan de slag

```bash
bundle add escalated
npm install @escalated-dev/escalated
rails generate escalated:install
rails db:migrate
```

Ga daarna naar `/support`. Vereist Ruby 3.1+ en Rails 7.1+. De [handleiding om te beginnen](../getting-started.md) behandelt de `Ticketable`-concern en de toegangscontroles.

## Meer weten

- [Alle functies](../features.md) · [Aan de slag](../getting-started.md) · [Frontend-integratie](../frontend-integration.md)
- [Configuratie, hostingmodi, events en routes](../operations.md) · [Benoemde routes](../named-routes.md)
- [Agentpaneel](../agent-panel.md) · [Toegangsbeheer](../access-control.md) · [Tickettoegang en routering](../ticket-access-and-routing.md)
- [Inkomende e-mail](../inbound-email.md) · [De widget insluiten](../embedding-the-widget.md) · [Het beheer insluiten](../embedding-admin.md)
- [Gasttoegang](../guest-access.md) · [Privébijlagen](../private-attachments.md)
- [Plugin-SDK](../plugin-sdk.md) · [Plugins](../plugins.md) · [Nieuwsbrieven](../newsletters.md)

Escalated is ook beschikbaar voor [Laravel](https://github.com/escalated-dev/escalated-laravel), [Django](https://github.com/escalated-dev/escalated-django), [NestJS](https://github.com/escalated-dev/escalated-nestjs), [AdonisJS](https://github.com/escalated-dev/escalated-adonis), [Symfony](https://github.com/escalated-dev/escalated-symfony), [Phoenix](https://github.com/escalated-dev/escalated-phoenix), [Go](https://github.com/escalated-dev/escalated-go), [.NET](https://github.com/escalated-dev/escalated-dotnet), [Spring](https://github.com/escalated-dev/escalated-spring), [WordPress](https://github.com/escalated-dev/escalated-wordpress) en [Filament](https://github.com/escalated-dev/escalated-filament). De UI staat in [escalated](https://github.com/escalated-dev/escalated).

## Licentie

MIT. Copyright (c) 2026 Escalated.dev. Zie [LICENSE](../../LICENSE).
