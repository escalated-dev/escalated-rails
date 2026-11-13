<p align="center"><sub>
  <a href="README.ar.md">العربية</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="../../README.md">English</a> ·
  <a href="README.es.md">Español</a> ·
  <b>Français</b> ·
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
  Ajoutez un helpdesk complet à votre application Rails.<br>
  Tickets, SLA, règles d'escalade, une boîte de réception pour les agents et un portail client, sur votre propre base de données.
</p>

<p align="center">
  <a href="https://escalated.dev"><b>Site web</b></a> ·
  <a href="https://escalated.dev/docs"><b>Documentation</b></a> ·
  <a href="https://escalated.dev/cloud"><b>Cloud</b></a> ·
  <a href="../../CHANGELOG.md"><b>Journal des modifications</b></a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-dark.png">
  <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-light.png" alt="La boîte de réception des agents d'Escalated : vues enregistrées avec compteurs, comptes à rebours SLA et priorités sur chaque ticket" width="100%">
</picture>

## Ce qu'il fait

<table>
  <tr>
    <td width="40%">
      <h3>Une boîte de réception où vos agents peuvent travailler toute la journée</h3>
      Conversation, notes internes, réponses types et minuteurs SLA sur un seul écran. Les tickets arrivent aussi par e-mail via Mailgun, Postmark, SES ou IMAP.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-light.png" alt="Un ticket ouvert dans l'espace de travail de l'agent avec l'éditeur de réponse">
      </picture>
    </td>
  </tr>
  <tr>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-light.png" alt="La page des rapports d'administration avec les temps de réponse, le CSAT et les dépassements de SLA">
      </picture>
    </td>
    <td width="40%">
      <h3>Des SLA et des règles d'escalade que vous voyez</h3>
      Objectifs de réponse et de résolution par priorité avec heures ouvrées, règles qui escaladent ou réassignent en cas de retard, et rapports sur les dépassements.
    </td>
  </tr>
  <tr>
    <td width="40%">
      <h3>Un portail client déjà prêt</h3>
      Vos clients ouvrent des tickets, répondent et suivent leur statut dans votre application. Intégrez le widget sur d'autres sites avec une seule balise script.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/portal-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/portal-light.png" alt="La liste des tickets du portail client">
      </picture>
    </td>
  </tr>
</table>

## Fonctionnalités

<table>
<tr>
<td width="33%" valign="top">

**Tickets et boîte de réception**
- Cycle de vie complet avec transitions de statut
- Filtres de file et actions groupées
- Notes internes et réponses types
- Scinder une réponse en nouveau ticket
- Mise en attente avec préréglages et réveil automatique
- Vues enregistrées et files partagées

</td>
<td width="33%" valign="top">

**SLA et escalade**
- Objectifs de réponse et de résolution par priorité
- Heures ouvrées et détection des dépassements
- Règles qui escaladent, réassignent ou notifient
- Routage par service en round-robin

</td>
<td width="33%" valign="top">

**Clients**
- Portail client en libre-service
- Tickets invités avec accès par lien magique
- Widget intégrable avec recherche dans la base de connaissances
- Base de connaissances publique que vous pouvez désactiver

</td>
</tr>
<tr>
<td width="33%" valign="top">

**E-mail**
- Réception via Mailgun, Postmark, SES ou IMAP
- Réponses regroupées en fils dans les clients de messagerie
- Modèles d'e-mail à votre image
- Notifications et webhooks par événement

</td>
<td width="33%" valign="top">

**Administration et accès**
- Services, SLA, règles, étiquettes et rapports
- Intégration facultative dans votre propre interface d'administration
- Rôles et permissions activables à l'installation
- Historique d'activité sur chaque ticket

</td>
<td width="33%" valign="top">

**Sous le capot**
- Interface partagée en Vue 3 et Inertia.js
- Envoi de fichiers avec stockage et limites de taille
- Étiquettes de couleur pour trier les tickets
- Temps réel avec ActionCable et repli sur le polling

</td>
</tr>
</table>

<p align="center"><sub><a href="../features.md">Toutes les fonctionnalités en détail</a></sub></p>

<p align="center"><b>Construit avec</b></p>

<p align="center">
  <a href="https://rubyonrails.org"><img src="https://img.shields.io/badge/Ruby%20on%20Rails-D30001?style=for-the-badge&logo=rubyonrails&logoColor=white" alt="Ruby on Rails"></a>
  <a href="https://www.ruby-lang.org"><img src="https://img.shields.io/badge/Ruby-CC342D?style=for-the-badge&logo=ruby&logoColor=white" alt="Ruby"></a>
  <a href="https://vuejs.org"><img src="https://img.shields.io/badge/Vue.js-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white" alt="Vue.js"></a>
  <a href="https://inertiajs.com"><img src="https://img.shields.io/badge/Inertia-9553E9?style=for-the-badge&logo=inertia&logoColor=white" alt="Inertia"></a>
</p>

## Démarrage rapide

```bash
bundle add escalated
npm install @escalated-dev/escalated
rails generate escalated:install
rails db:migrate
```

Rendez-vous ensuite sur `/support`. Nécessite Ruby 3.1+ et Rails 7.1+. Le [guide de démarrage](../getting-started.md) explique le concern `Ticketable` et les vérifications d'accès.

## En savoir plus

- [Toutes les fonctionnalités](../features.md) · [Premiers pas](../getting-started.md) · [Intégration frontend](../frontend-integration.md)
- [Configuration, modes d'hébergement, événements et routes](../operations.md) · [Routes nommées](../named-routes.md)
- [Panneau agent](../agent-panel.md) · [Contrôle d'accès](../access-control.md) · [Accès aux tickets et routage](../ticket-access-and-routing.md)
- [E-mail entrant](../inbound-email.md) · [Intégrer le widget](../embedding-the-widget.md) · [Intégrer l'administration](../embedding-admin.md)
- [Accès invité](../guest-access.md) · [Pièces jointes privées](../private-attachments.md)
- [Plugin SDK](../plugin-sdk.md) · [Plugins](../plugins.md) · [Newsletters](../newsletters.md)

Escalated est aussi disponible pour [Laravel](https://github.com/escalated-dev/escalated-laravel), [Django](https://github.com/escalated-dev/escalated-django), [NestJS](https://github.com/escalated-dev/escalated-nestjs), [AdonisJS](https://github.com/escalated-dev/escalated-adonis), [Symfony](https://github.com/escalated-dev/escalated-symfony), [Phoenix](https://github.com/escalated-dev/escalated-phoenix), [Go](https://github.com/escalated-dev/escalated-go), [.NET](https://github.com/escalated-dev/escalated-dotnet), [Spring](https://github.com/escalated-dev/escalated-spring), [WordPress](https://github.com/escalated-dev/escalated-wordpress) et [Filament](https://github.com/escalated-dev/escalated-filament). L'interface se trouve dans [escalated](https://github.com/escalated-dev/escalated).

## Licence

MIT. Copyright (c) 2026 Escalated.dev. Voir [LICENSE](../../LICENSE).
