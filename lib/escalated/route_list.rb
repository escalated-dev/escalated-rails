# frozen_string_literal: true

module Escalated
  # The named routes the shared frontend calls through `route(name, params)`
  # (Laravel's Ziggy helper), mapped to the paths this engine serves them at.
  #
  # Shared with every Escalated Inertia page as the `ziggy` prop, in the shape
  # ziggy-js reads, and resolved in the browser by ROUTE_HELPER (the
  # escalated_route_helper_tag view helper). A host that installs its
  # own window.route, or sets window.Ziggy, wins; config.route_overrides
  # replaces or adds individual names on the server side.
  #
  # Paths are relative to the engine mount (config.route_prefix) and use the
  # engine's own parameter names, so positional and keyed params both work.
  # spec/lib/escalated/route_list_spec.rb checks every entry against the router
  # and every name the frontend calls against this list.
  module RouteList
    GET = %w[GET HEAD].freeze
    POST = %w[POST].freeze
    PUT = %w[PUT PATCH].freeze
    PATCH = %w[PATCH].freeze
    DELETE = %w[DELETE].freeze

    # The Laravel-style CRUD names of a `resources` block:
    # index, create (the form), store, edit, update, destroy.
    def self.crud(name, path, only: %i[index create store edit update destroy])
      {
        index: [path, GET], create: ["#{path}/new", GET], store: [path, POST],
        edit: ["#{path}/{id}/edit", GET], update: ["#{path}/{id}", PUT], destroy: ["#{path}/{id}", DELETE]
      }.slice(*only).to_h { |action, route| ["escalated.admin.#{name}.#{action}", route] }
    end

    # Ticket actions shared by the agent and admin ticket screens.
    def self.ticket_actions(area)
      base = "#{area}/tickets"
      {
        "escalated.#{area}.tickets.index" => [base, GET],
        "escalated.#{area}.tickets.bulk" => ["#{base}/bulk", POST],
        "escalated.#{area}.tickets.show" => ["#{base}/{id}", GET],
        "escalated.#{area}.tickets.pin" => ["#{base}/{id}/replies/{reply_id}/pin", POST]
      }.merge(
        %w[reply note assign status priority tags department macro follow presence].to_h do |action|
          ["escalated.#{area}.tickets.#{action}", ["#{base}/{id}/#{action}", POST]]
        end
      )
    end

    ENTRIES = {
      # Agent
      'escalated.agent.dashboard' => ['agent', GET],
      **ticket_actions('agent'),
      'escalated.agent.tickets.update' => ['agent/tickets/{id}', PUT],
      'escalated.agent.tickets.custom-action' => ['agent/tickets/{id}/actions/{action_key}', POST],

      # Admin tickets
      **ticket_actions('admin'),
      'escalated.admin.tickets.snooze' => ['admin/tickets/{id}/snooze', POST],
      'escalated.admin.tickets.unsnooze' => ['admin/tickets/{id}/unsnooze', POST],
      'escalated.admin.tickets.split' => ['admin/tickets/{id}/split', POST],

      # Admin configuration screens
      **crud('departments', 'admin/departments'),
      **crud('sla-policies', 'admin/sla_policies'),
      **crud('escalation-rules', 'admin/escalation_rules'),
      **crud('statuses', 'admin/statuses'),
      **crud('business-hours', 'admin/business_hours'),
      **crud('roles', 'admin/roles'),
      **crud('skills', 'admin/skills'),
      **crud('automations', 'admin/automations'),
      **crud('webhooks', 'admin/webhooks'),
      **crud('custom-fields', 'admin/custom_fields'),
      **crud('custom-objects', 'admin/custom_objects'),
      **crud('kb-articles', 'admin/articles'),
      **crud('kb-categories', 'admin/kb_categories', only: %i[index store update destroy]),
      **crud('tags', 'admin/tags', only: %i[index store update destroy]),
      **crud('canned-responses', 'admin/canned_responses', only: %i[index store update destroy]),
      **crud('macros', 'admin/macros', only: %i[index store update destroy]),
      **crud('saved-views', 'admin/saved_views', only: %i[index store update destroy]),
      **crud('api-tokens', 'admin/api_tokens', only: %i[index store update destroy]),
      **crud('workflows', 'admin/workflows'),
      'escalated.admin.custom-fields.reorder' => ['admin/custom_fields/reorder', POST],
      'escalated.admin.saved-views.reorder' => ['admin/saved_views/reorder', POST],
      'escalated.admin.custom-objects.records' => ['admin/custom_objects/{id}/records', GET],
      'escalated.admin.custom-objects.records.store' => ['admin/custom_objects/{id}/records', POST],
      'escalated.admin.custom-objects.records.update' => ['admin/custom_objects/{id}/records/{record_id}', %w[PUT]],
      'escalated.admin.custom-objects.records.destroy' => ['admin/custom_objects/{id}/records/{record_id}', DELETE],
      'escalated.admin.webhooks.deliveries' => ['admin/webhooks/{id}/deliveries', GET],
      'escalated.admin.webhooks.retry' => ['admin/webhooks/deliveries/{delivery_id}/retry', POST],
      'escalated.admin.workflows.toggle' => ['admin/workflows/{id}/toggle', POST],
      'escalated.admin.workflows.reorder' => ['admin/workflows/reorder', POST],
      'escalated.admin.capacity.index' => ['admin/capacity', GET],
      'escalated.admin.capacity.update' => ['admin/capacity/{id}', PUT],
      'escalated.admin.audit-log' => ['admin/audit_logs', GET],
      'escalated.admin.users.index' => ['admin/users', GET],
      'escalated.admin.users.role' => ['admin/users/{user_id}/role', PATCH],
      'escalated.admin.users.roles' => ['admin/users/{user_id}/roles', %w[PUT]],
      'escalated.admin.plugins.index' => ['admin/plugins', GET],
      'escalated.admin.plugins.upload' => ['admin/plugins/upload', POST],
      'escalated.admin.plugins.activate' => ['admin/plugins/{id}/activate', POST],
      'escalated.admin.plugins.deactivate' => ['admin/plugins/{id}/deactivate', POST],
      'escalated.admin.plugins.destroy' => ['admin/plugins/{id}', DELETE],
      'escalated.admin.chat.end' => ['admin/chat/{id}/end', POST],
      'escalated.admin.chat.transfer' => ['admin/chat/{id}/transfer', POST],

      # Reports
      'escalated.admin.reports' => ['admin/reports', GET],
      'escalated.admin.reports.dashboard' => ['admin/reports/dashboard', GET],
      'escalated.admin.reports.agents' => ['admin/reports/agents', GET],
      'escalated.admin.reports.sla' => ['admin/reports/sla', GET],
      'escalated.admin.reports.csat' => ['admin/reports/csat', GET],
      'escalated.admin.reports.agent-detail' => ['admin/reports/agent/{id}/detail', GET],
      'escalated.admin.reports.sla-trends' => ['admin/reports/advanced/sla_trends', GET],
      'escalated.admin.reports.response-times' => ['admin/reports/advanced/response_times', GET],
      'escalated.admin.reports.resolution-times' => ['admin/reports/advanced/resolution_times', GET],
      'escalated.admin.reports.agent-ranking' => ['admin/reports/advanced/agent_ranking', GET],
      'escalated.admin.reports.cohorts' => ['admin/reports/advanced/cohorts', GET],
      'escalated.admin.reports.comparison' => ['admin/reports/advanced/comparison', GET],

      # Settings
      'escalated.admin.settings' => ['admin/settings', GET],
      'escalated.admin.settings.update' => ['admin/settings', POST],
      'escalated.admin.settings.csat' => ['admin/settings/csat', GET],
      'escalated.admin.settings.csat.update' => ['admin/settings/csat', POST],
      'escalated.admin.settings.data-retention' => ['admin/settings/data-retention', GET],
      'escalated.admin.settings.data-retention.update' => ['admin/settings/data-retention', POST],
      'escalated.admin.settings.email' => ['admin/settings/email', GET],
      'escalated.admin.settings.email.update' => ['admin/settings/email', POST],
      'escalated.admin.settings.public-tickets' => ['admin/settings/public-tickets', GET],
      'escalated.admin.settings.public-tickets.update' => ['admin/settings/public-tickets', %w[PUT POST]],
      'escalated.admin.settings.sso' => ['admin/settings/sso', GET],
      'escalated.admin.settings.sso.update' => ['admin/settings/sso', POST],
      'escalated.admin.settings.database' => ['admin/settings/database', GET],
      'escalated.admin.settings.database.test' => ['admin/settings/database/test', POST],
      'escalated.admin.settings.database.update' => ['admin/settings/database', POST],

      # Import wizard
      'escalated.admin.import.index' => ['admin/import', GET],
      'escalated.admin.import.connect' => ['admin/import/{platform}/connect', GET],
      'escalated.admin.import.test-connection' => ['admin/import/{platform}/test-connection', POST],
      'escalated.admin.import.mapping' => ['admin/import/{platform}/mapping', GET],
      'escalated.admin.import.review' => ['admin/import/{platform}/review', POST],
      'escalated.admin.import.start' => ['admin/import/{platform}/start', POST],
      'escalated.admin.import.progress' => ['admin/import/progress/{job_id}', GET],
      'escalated.admin.import.status' => ['admin/import/status/{job_id}', GET],
      'escalated.admin.import.pause' => ['admin/import/pause/{job_id}', POST],
      'escalated.admin.import.resume' => ['admin/import/resume/{job_id}', POST],
      'escalated.admin.import.cancel' => ['admin/import/cancel/{job_id}', POST],

      # Two-factor (ADR 2026-10-29): enrolment and the post-login challenge
      'escalated.admin.two-factor.index' => ['admin/settings/two-factor', GET],
      'escalated.admin.two-factor.setup' => ['admin/settings/two-factor/setup', POST],
      'escalated.admin.two-factor.confirm' => ['admin/settings/two-factor/confirm', POST],
      'escalated.admin.two-factor.disable' => ['admin/settings/two-factor/disable', POST],
      'escalated.two-factor.challenge' => ['two-factor/challenge', GET],
      'escalated.two-factor.verify' => ['two-factor/challenge', POST],

      # Single sign-on
      'escalated.sso.login' => ['sso/login', GET],

      # Customer
      'escalated.customer.tickets.index' => ['customer/tickets', GET],
      'escalated.customer.tickets.create' => ['customer/tickets/create', GET],
      'escalated.customer.tickets.store' => ['customer/tickets', POST],
      'escalated.customer.tickets.show' => ['customer/tickets/{id}', GET],
      'escalated.customer.tickets.reply' => ['customer/tickets/{id}/reply', POST],
      'escalated.customer.tickets.close' => ['customer/tickets/{id}/close', POST],
      'escalated.customer.tickets.reopen' => ['customer/tickets/{id}/reopen', POST],
      'escalated.customer.tickets.rate' => ['customer/tickets/{id}/rate', POST],
      'escalated.customer.kb.index' => ['customer/kb', GET],
      'escalated.customer.kb.show' => ['customer/kb/{slug}', GET],
      'escalated.customer.kb.feedback' => ['customer/kb/{slug}/feedback', POST],

      # Guest
      'escalated.guest.tickets.create' => ['guest/create', GET],
      'escalated.guest.tickets.store' => ['guest', POST],
      'escalated.guest.tickets.show' => ['guest/{token}', GET],
      'escalated.guest.tickets.reply' => ['guest/{token}/reply', POST],
      'escalated.guest.tickets.rate' => ['guest/{token}/rate', POST],
      'escalated.guest.verification' => ['guest/verification', POST],
      'escalated.guest.lookup' => ['guest/lookup', POST],

      # Attachments (signed links; the frontend mostly uses the url it is sent)
      'escalated.attachments.download' => ['attachments/{id}', GET]
    }.freeze

    # A small Ziggy-compatible route() for hosts without ziggy-js. Installed
    # only when window.route is not already a function; reads window.Ziggy
    # first, then the `ziggy` prop of the Inertia page; an unknown name warns
    # and returns '#'. The page is read on first call, so the tag may sit in
    # <head>, ahead of the Inertia root element.
    ROUTE_HELPER = <<~'JS'
      (function () {
        if (typeof window.route === 'function') return;
        var ziggy = null;
        function table() {
          if (ziggy) return ziggy;
          try {
            var el = document.querySelector('script[data-page]');
            var root = document.querySelector('[data-page]');
            var page = el && el.tagName === 'SCRIPT' ? JSON.parse(el.textContent) : JSON.parse(root.getAttribute('data-page'));
            ziggy = (page.props && page.props.ziggy) || null;
          } catch (e) { ziggy = null; }
          return ziggy || {};
        }
        window.route = function (name, params) {
          var routes = (window.Ziggy && window.Ziggy.routes) || table().routes || {};
          var route = routes[name];
          if (!route) {
            if (window.console) console.warn('[escalated] no route named ' + name);
            return '#';
          }
          var list = params == null ? [] : (Array.isArray(params) ? params.slice() : (typeof params === 'object' ? null : [params]));
          var query = {};
          if (list === null) { for (var k in params) query[k] = params[k]; }
          var uri = route.uri.replace(/\{(\w+)\??\}/g, function (_, key) {
            var value;
            if (list !== null) { value = list.shift(); }
            else { value = query[key]; delete query[key]; }
            if (value != null && typeof value === 'object') value = value.reference != null ? value.reference : value.id;
            return value == null ? '' : encodeURIComponent(value);
          }).replace(/\/+$/, '');
          var search = Object.keys(query).filter(function (key) { return query[key] != null; })
            .map(function (key) { return encodeURIComponent(key) + '=' + encodeURIComponent(query[key]); }).join('&');
          return '/' + uri + (search ? '?' + search : '');
        };
      })();
    JS

    module_function

    # name => { uri:, methods: }, uri without a leading slash, under the
    # configured route prefix, with config.route_overrides merged over it.
    def routes
      prefix = Escalated.configuration.route_prefix.to_s.gsub(%r{\A/+|/+\z}, '')
      built = ENTRIES.to_h do |name, (path, methods)|
        [name, { uri: [prefix, path].reject(&:empty?).join('/'), methods: methods }]
      end

      built.merge(overrides)
    end

    # The `ziggy` prop for one request.
    def ziggy(request)
      {
        url: request.base_url,
        port: nil,
        defaults: {},
        routes: routes,
        location: request.original_url
      }
    end

    def overrides
      (Escalated.configuration.route_overrides || {}).to_h do |name, entry|
        entry = { uri: entry } unless entry.is_a?(Hash)
        entry = entry.symbolize_keys
        [name.to_s, { uri: entry[:uri].to_s.delete_prefix('/'), methods: Array(entry[:methods] || GET) }]
      end
    end
  end
end
