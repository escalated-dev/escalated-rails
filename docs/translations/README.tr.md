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
  <a href="README.pl.md">Polski</a> ·
  <a href="README.pt-BR.md">Português (BR)</a> ·
  <a href="README.ru.md">Русский</a> ·
  <b>Türkçe</b> ·
  <a href="README.zh-CN.md">简体中文</a>
</sub></p>

<p align="center">
  <a href="https://escalated.dev"><img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/logo.png" width="72" height="72" alt="Escalated"></a>
</p>

<h1 align="center">Escalated for Rails</h1>

<p align="center">
  Rails uygulamana eksiksiz bir yardım masası ekle.<br>
  Talepler, SLA'lar, eskalasyon kuralları, temsilciler için bir gelen kutusu ve bir müşteri portalı, hepsi kendi veritabanında çalışır.
</p>

<p align="center">
  <a href="https://escalated.dev"><b>Web sitesi</b></a> ·
  <a href="https://escalated.dev/docs"><b>Belgeler</b></a> ·
  <a href="https://escalated.dev/cloud"><b>Cloud</b></a> ·
  <a href="../../CHANGELOG.md"><b>Değişiklik günlüğü</b></a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-dark.png">
  <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-light.png" alt="Escalated temsilci gelen kutusu: sayaçlı kayıtlı görünümler, SLA geri sayımları ve her talepte öncelikler" width="100%">
</picture>

## Ne yapar

<table>
  <tr>
    <td width="40%">
      <h3>Temsilcilerinin bütün gün çalışabileceği bir gelen kutusu</h3>
      Konuşma, dahili notlar, hazır yanıtlar ve SLA sayaçları tek ekranda. Talepler Mailgun, Postmark, SES veya IMAP üzerinden e-postayla da gelir.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-light.png" alt="Temsilci çalışma alanında yanıt düzenleyicisiyle açık bir talep">
      </picture>
    </td>
  </tr>
  <tr>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-light.png" alt="Yanıt süreleri, CSAT ve SLA ihlalleriyle yönetici raporlar sayfası">
      </picture>
    </td>
    <td width="40%">
      <h3>Görebildiğin SLA'lar ve eskalasyon kuralları</h3>
      Mesai saatleriyle birlikte önceliğe göre yanıt ve çözüm hedefleri, bir hedef kaçırıldığında eskale eden veya yeniden atayan kurallar ve ihlal raporları.
    </td>
  </tr>
  <tr>
    <td width="40%">
      <h3>Hazır gelen bir müşteri portalı</h3>
      Müşteriler senin uygulamanın içinde talep açar, yanıt verir ve durumu kontrol eder. Widget'ı tek bir script etiketiyle başka sitelere yerleştirebilirsin.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/portal-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/portal-light.png" alt="Müşteri portalındaki talep listesi">
      </picture>
    </td>
  </tr>
</table>

## Özellikler

<table>
<tr>
<td width="33%" valign="top">

**Talepler ve gelen kutusu**
- Durum geçişleriyle tam yaşam döngüsü
- Kuyruk filtreleri ve toplu işlemler
- Dahili notlar ve hazır yanıtlar
- Bir yanıtı yeni bir talebe ayırma
- Ön ayarlar ve otomatik uyandırmayla erteleme
- Kayıtlı görünümler ve paylaşılan kuyruklar

</td>
<td width="33%" valign="top">

**SLA'lar ve eskalasyon**
- Önceliğe göre yanıt ve çözüm hedefleri
- Mesai saatleri ve ihlal tespiti
- Eskale eden, yeniden atayan veya bildirim gönderen kurallar
- Round-robin ile departman yönlendirmesi

</td>
<td width="33%" valign="top">

**Müşteriler**
- Self servis müşteri portalı
- Magic link erişimli misafir talepleri
- Bilgi bankası aramalı yerleştirilebilir widget
- Kapatabileceğin herkese açık bilgi bankası

</td>
</tr>
<tr>
<td width="33%" valign="top">

**E-posta**
- Mailgun, Postmark, SES veya IMAP üzerinden gelen e-posta
- E-posta istemcilerinde zincirlenmiş yanıtlar
- Markana uygun e-posta şablonları
- Olay bazında bildirimler ve webhook'lar

</td>
<td width="33%" valign="top">

**Yönetim ve erişim**
- Departmanlar, SLA'lar, kurallar, etiketler ve raporlar
- İsteğe bağlı olarak kendi yönetim panelinde gömülü kullanım
- Kurulumda açılıp kapatılabilen roller ve izinler
- Her talepte etkinlik zaman çizelgesi

</td>
<td width="33%" valign="top">

**Perde arkası**
- Vue 3 ve Inertia.js ile paylaşılan arayüz
- Depolama ve boyut sınırlarıyla dosya yüklemeleri
- Talepleri düzenlemek için renkli etiketler
- Yedek olarak yoklamayla ActionCable gerçek zamanlı güncellemeler

</td>
</tr>
</table>

<p align="center"><sub><a href="../features.md">Tüm özellikler ayrıntılı olarak</a></sub></p>

<p align="center"><b>Kullanılan teknolojiler</b></p>

<p align="center">
  <a href="https://rubyonrails.org"><img src="https://img.shields.io/badge/Ruby%20on%20Rails-D30001?style=for-the-badge&logo=rubyonrails&logoColor=white" alt="Ruby on Rails"></a>
  <a href="https://www.ruby-lang.org"><img src="https://img.shields.io/badge/Ruby-CC342D?style=for-the-badge&logo=ruby&logoColor=white" alt="Ruby"></a>
  <a href="https://vuejs.org"><img src="https://img.shields.io/badge/Vue.js-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white" alt="Vue.js"></a>
  <a href="https://inertiajs.com"><img src="https://img.shields.io/badge/Inertia-9553E9?style=for-the-badge&logo=inertia&logoColor=white" alt="Inertia"></a>
</p>

## Hızlı başlangıç

```bash
bundle add escalated
npm install @escalated-dev/escalated
rails generate escalated:install
rails db:migrate
```

Ardından `/support` adresini aç. Ruby 3.1+ ve Rails 7.1+ gerekir. [Başlangıç kılavuzu](../getting-started.md) `Ticketable` concern'ünü ve erişim kontrollerini anlatır.

## Daha fazla bilgi

- [Tüm özellikler](../features.md) · [Başlarken](../getting-started.md) · [Frontend entegrasyonu](../frontend-integration.md)
- [Yapılandırma, barındırma modları, olaylar ve rotalar](../operations.md) · [Adlandırılmış rotalar](../named-routes.md)
- [Temsilci paneli](../agent-panel.md) · [Erişim denetimi](../access-control.md) · [Talep erişimi ve yönlendirme](../ticket-access-and-routing.md)
- [Gelen e-posta](../inbound-email.md) · [Widget'ı yerleştirme](../embedding-the-widget.md) · [Yönetim panelini yerleştirme](../embedding-admin.md)
- [Misafir erişimi](../guest-access.md) · [Özel ekler](../private-attachments.md)
- [Eklenti SDK'sı](../plugin-sdk.md) · [Eklentiler](../plugins.md) · [Bültenler](../newsletters.md)

Escalated ayrıca [Laravel](https://github.com/escalated-dev/escalated-laravel), [Django](https://github.com/escalated-dev/escalated-django), [NestJS](https://github.com/escalated-dev/escalated-nestjs), [AdonisJS](https://github.com/escalated-dev/escalated-adonis), [Symfony](https://github.com/escalated-dev/escalated-symfony), [Phoenix](https://github.com/escalated-dev/escalated-phoenix), [Go](https://github.com/escalated-dev/escalated-go), [.NET](https://github.com/escalated-dev/escalated-dotnet), [Spring](https://github.com/escalated-dev/escalated-spring), [WordPress](https://github.com/escalated-dev/escalated-wordpress) ve [Filament](https://github.com/escalated-dev/escalated-filament) için de mevcut. Arayüz [escalated](https://github.com/escalated-dev/escalated) deposunda bulunur.

## Lisans

MIT. Copyright (c) 2026 Escalated.dev. Bkz. [LICENSE](../../LICENSE).
