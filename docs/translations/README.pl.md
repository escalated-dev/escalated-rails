<p align="center"><sub>
  <a href="README.ar.md">العربية</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="../../README.md">English</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.it.md">Italiano</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.nl.md">Nederlands</a> ·
  <b>Polski</b> ·
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
  Dodaj kompletny helpdesk do swojej aplikacji Rails.<br>
  Zgłoszenia, SLA, reguły eskalacji, skrzynka dla agentów i portal klienta, działające na twojej własnej bazie danych.
</p>

<p align="center">
  <a href="https://escalated.dev"><b>Strona</b></a> ·
  <a href="https://escalated.dev/docs"><b>Dokumentacja</b></a> ·
  <a href="https://escalated.dev/cloud"><b>Cloud</b></a> ·
  <a href="../../CHANGELOG.md"><b>Lista zmian</b></a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-dark.png">
  <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-light.png" alt="Skrzynka agenta w Escalated: zapisane widoki z licznikami, odliczanie SLA i priorytety przy każdym zgłoszeniu" width="100%">
</picture>

## Co robi

<table>
  <tr>
    <td width="40%">
      <h3>Skrzynka, w której agenci mogą pracować cały dzień</h3>
      Rozmowa, notatki wewnętrzne, gotowe odpowiedzi i liczniki SLA na jednym ekranie. Zgłoszenia przychodzą też e-mailem przez Mailgun, Postmark, SES lub IMAP.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-light.png" alt="Zgłoszenie otwarte w obszarze roboczym agenta z edytorem odpowiedzi">
      </picture>
    </td>
  </tr>
  <tr>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-light.png" alt="Strona raportów w panelu administracyjnym z czasami odpowiedzi, CSAT i naruszeniami SLA">
      </picture>
    </td>
    <td width="40%">
      <h3>SLA i reguły eskalacji, które widzisz</h3>
      Cele czasu odpowiedzi i rozwiązania dla każdego priorytetu z godzinami pracy, reguły, które eskalują lub przypisują ponownie, gdy cel nie zostanie dotrzymany, oraz raporty naruszeń.
    </td>
  </tr>
  <tr>
    <td width="40%">
      <h3>Portal klienta, który jest już gotowy</h3>
      Klienci zakładają zgłoszenia, odpowiadają i sprawdzają status w twojej aplikacji. Widżet osadzisz na innych stronach jednym tagiem script.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/portal-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/portal-light.png" alt="Lista zgłoszeń w portalu klienta">
      </picture>
    </td>
  </tr>
</table>

## Funkcje

<table>
<tr>
<td width="33%" valign="top">

**Zgłoszenia i skrzynka**
- Pełny cykl życia z przejściami statusów
- Filtry kolejek i akcje zbiorcze
- Notatki wewnętrzne i gotowe odpowiedzi
- Wydzielenie odpowiedzi do nowego zgłoszenia
- Odkładanie z presetami i automatycznym wybudzaniem
- Zapisane widoki i wspólne kolejki

</td>
<td width="33%" valign="top">

**SLA i eskalacja**
- Cele odpowiedzi i rozwiązania dla każdego priorytetu
- Godziny pracy i wykrywanie naruszeń
- Reguły, które eskalują, przypisują ponownie lub powiadamiają
- Kierowanie do działów metodą round-robin

</td>
<td width="33%" valign="top">

**Klienci**
- Samoobsługowy portal klienta
- Zgłoszenia gości z dostępem przez magic link
- Osadzany widżet z wyszukiwaniem w bazie wiedzy
- Publiczna baza wiedzy, którą możesz wyłączyć

</td>
</tr>
<tr>
<td width="33%" valign="top">

**E-mail**
- Poczta przychodząca przez Mailgun, Postmark, SES lub IMAP
- Odpowiedzi w wątkach w klientach poczty
- Szablony e-maili z twoim brandingiem
- Powiadomienia i webhooki dla poszczególnych zdarzeń

</td>
<td width="33%" valign="top">

**Administracja i dostęp**
- Działy, SLA, reguły, tagi i raporty
- Opcjonalne osadzenie we własnym panelu administracyjnym
- Role i uprawnienia jako przełącznik przy instalacji
- Oś czasu aktywności przy każdym zgłoszeniu

</td>
<td width="33%" valign="top">

**Pod maską**
- Wspólny interfejs w Vue 3 i Inertia.js
- Przesyłanie plików z limitami miejsca i rozmiaru
- Kolorowe tagi do porządkowania zgłoszeń
- Czas rzeczywisty przez ActionCable z odpytywaniem jako zapasem

</td>
</tr>
</table>

<p align="center"><sub><a href="../features.md">Wszystkie funkcje szczegółowo</a></sub></p>

<p align="center"><b>Zbudowane z użyciem</b></p>

<p align="center">
  <a href="https://rubyonrails.org"><img src="https://img.shields.io/badge/Ruby%20on%20Rails-D30001?style=for-the-badge&logo=rubyonrails&logoColor=white" alt="Ruby on Rails"></a>
  <a href="https://www.ruby-lang.org"><img src="https://img.shields.io/badge/Ruby-CC342D?style=for-the-badge&logo=ruby&logoColor=white" alt="Ruby"></a>
  <a href="https://vuejs.org"><img src="https://img.shields.io/badge/Vue.js-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white" alt="Vue.js"></a>
  <a href="https://inertiajs.com"><img src="https://img.shields.io/badge/Inertia-9553E9?style=for-the-badge&logo=inertia&logoColor=white" alt="Inertia"></a>
</p>

## Szybki start

```bash
bundle add escalated
npm install @escalated-dev/escalated
rails generate escalated:install
rails db:migrate
```

Następnie otwórz `/support`. Wymaga Ruby 3.1+ i Rails 7.1+. [Przewodnik na start](../getting-started.md) omawia concern `Ticketable` i kontrole dostępu.

## Dowiedz się więcej

- [Wszystkie funkcje](../features.md) · [Pierwsze kroki](../getting-started.md) · [Integracja frontendu](../frontend-integration.md)
- [Konfiguracja, tryby hostingu, zdarzenia i trasy](../operations.md) · [Nazwane trasy](../named-routes.md)
- [Panel agenta](../agent-panel.md) · [Kontrola dostępu](../access-control.md) · [Dostęp do zgłoszeń i kierowanie](../ticket-access-and-routing.md)
- [Poczta przychodząca](../inbound-email.md) · [Osadzanie widżetu](../embedding-the-widget.md) · [Osadzanie panelu administracyjnego](../embedding-admin.md)
- [Dostęp dla gości](../guest-access.md) · [Prywatne załączniki](../private-attachments.md)
- [SDK wtyczek](../plugin-sdk.md) · [Wtyczki](../plugins.md) · [Newslettery](../newsletters.md)

Escalated jest dostępny także dla [Laravel](https://github.com/escalated-dev/escalated-laravel), [Django](https://github.com/escalated-dev/escalated-django), [NestJS](https://github.com/escalated-dev/escalated-nestjs), [AdonisJS](https://github.com/escalated-dev/escalated-adonis), [Symfony](https://github.com/escalated-dev/escalated-symfony), [Phoenix](https://github.com/escalated-dev/escalated-phoenix), [Go](https://github.com/escalated-dev/escalated-go), [.NET](https://github.com/escalated-dev/escalated-dotnet), [Spring](https://github.com/escalated-dev/escalated-spring), [WordPress](https://github.com/escalated-dev/escalated-wordpress) i [Filament](https://github.com/escalated-dev/escalated-filament). Interfejs znajduje się w [escalated](https://github.com/escalated-dev/escalated).

## Licencja

MIT. Copyright (c) 2026 Escalated.dev. Zobacz [LICENSE](../../LICENSE).
