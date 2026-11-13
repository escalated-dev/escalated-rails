# Frontend integration

## Frontend Setup

Escalated uses Inertia.js with Vue 3. The frontend components are provided by the [`@escalated-dev/escalated`](https://github.com/escalated-dev/escalated) npm package.

### Tailwind Content

Add the Escalated package to your Tailwind `content` config so its classes aren't purged:

```js
// tailwind.config.js
content: [
    // ... your existing paths
    './node_modules/@escalated-dev/escalated/src/**/*.vue',
],
```

### Page Resolver

Add the Escalated pages to your Inertia page resolver:

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

### Named routes

The shared components build URLs with Laravel's Ziggy-style `route(name, params)`. The engine ships the list itself: every Escalated Inertia page gets a `ziggy` prop with the names mapped to this engine's paths under `route_prefix`. Install the matching `route()` helper in your Inertia layout, before the script that mounts the app:

```erb
<%= escalated_route_helper_tag %>
<%= vite_javascript_tag 'application' %>
```

No hand-mapped `window.route` shim is needed. A `window.route` or `window.Ziggy` your app already installs still wins, and `config.route_overrides` replaces or adds single names (for example `'login' => '/users/sign_in'`). See [docs/named-routes.md](named-routes.md).

### Theming (Optional)

Register the `EscalatedPlugin` to render Escalated pages inside your app's layout — no page duplication needed:

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

See the [`@escalated-dev/escalated` README](https://github.com/escalated-dev/escalated) for full theming documentation and CSS custom properties.

## Internationalization

Translations are sourced from the central [`escalated-locale`](https://github.com/escalated-dev/escalated-locale)
RubyGem, which is the canonical source of truth for every Escalated
plugin in the portfolio. The engine appends the gem's `locales/*.yml`
files to `I18n.load_path` automatically — you do not need to require
anything in your host app.

Override order (last wins):

1. `escalated-locale` gem — central, portfolio-wide
2. `config/locales/*.yml` inside this engine — plugin-local overrides
3. `config/locales/overrides/*.yml` inside this engine — host-specific
   tweaks that should not be upstreamed
4. The host application's own `config/locales/*.yml`

Missing keys in the lower layers fall through to the central gem via
`I18n.fallbacks`.
