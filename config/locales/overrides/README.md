# Locale overrides

Drop `*.yml` files in this directory to override individual keys from
the central `escalated-locale` gem or the plugin-local
`config/locales/*.yml` files.

Rails I18n loads translations in this order (last wins):

1. `escalated-locale` gem (canonical, portfolio-wide)
2. `config/locales/*.yml` (plugin-local)
3. `config/locales/overrides/*.yml` (this directory)

Files here are intended for host-specific tweaks that should not be
upstreamed to the shared gem.
