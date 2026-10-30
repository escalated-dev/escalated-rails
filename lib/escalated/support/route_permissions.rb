# frozen_string_literal: true

module Escalated
  module Support
    # The permission each admin, agent and staff API action requires while
    # roles & permissions is enforced (ADR 2026-10-29-configurable-access-features).
    #
    # escalated-laravel's src/Support/RoutePermissions.php, keyed by
    # "controller#action" instead of a route name. Entries are tried in order
    # and the first match wins; patterns use File.fnmatch with `{a,b}`
    # alternation. An action matching nothing is refused, and a spec walks the
    # routes so a new one cannot ship without an entry here.
    #
    # Every slug is one db/seeds/permissions.rb seeds. An empty list means
    # "staff, no particular permission" and is kept for personal screens.
    module RoutePermissions
      # Statuses whose change needs ticket.close as well as ticket.edit.
      CLOSING_STATUSES = %w[resolved closed reopened].freeze

      # Bulk actions and the permission each needs.
      BULK_ACTIONS = {
        'status' => %w[ticket.edit],
        'priority' => %w[ticket.edit],
        'assign' => %w[ticket.assign],
        'tag' => %w[ticket.edit],
        'tags' => %w[ticket.edit],
        'department' => %w[ticket.edit],
        'close' => %w[ticket.edit ticket.close],
        'delete' => %w[ticket.delete]
      }.freeze

      A = 'escalated/admin'
      G = 'escalated/agent'
      API = 'escalated/api/v1'
      STAFF = 'escalated/{admin,agent}'
      VIEW = %w[ticket.view].freeze
      EDIT = %w[ticket.edit].freeze

      # index (and other reads) => group.view; new/edit forms and writes =>
      # group.manage, as Laravel's resource() helper.
      def self.resource(controller, group, reads: %w[index show])
        [
          ["#{A}/#{controller}\#{#{reads.join(',')}}", ["#{group}.view"]],
          ["#{A}/#{controller}#*", ["#{group}.manage"]]
        ]
      end

      MAP = [
        # ---- Personal ------------------------------------------------------
        ["#{A}/two_factor#*", []],

        # ---- Tickets (admin and agent panels, staff API) ---------------------
        ["#{G}/dashboard#index", VIEW],
        ["#{API}/dashboard#index", VIEW],
        ["#{API}/auth\#{validate,me,profile}", []],
        ["#{API}/resources\#{agents,departments,tags,canned_responses,realtime_config}", VIEW],
        ["#{API}/resources#macros", %w[macro.view]],
        ["#{G}/mentions#*", VIEW],

        ["#{STAFF}/tickets\#{index,show,follow,presence}", VIEW],
        ["#{API}/tickets\#{index,show,follow}", VIEW],
        ["#{A}/ticket_links#index", VIEW],
        ["#{A}/ticket_merges#search", VIEW],
        ["#{A}/side_conversations#index", VIEW],

        ["#{API}/tickets#create", %w[ticket.create]],
        ["#{A}/tickets#split", %w[ticket.create]],
        ["#{G}/tickets#update", EDIT],
        ["#{STAFF}/tickets\#{status,priority,tags,department,pin,custom_action,snooze,unsnooze}", EDIT],
        ["#{API}/tickets\#{status,priority,tags,custom_action}", EDIT],
        ["#{STAFF}/ticket_subjects#*", EDIT],
        ["#{A}/ticket_links\#{store,destroy}", EDIT],
        ["#{STAFF}/tickets#assign", %w[ticket.assign]],
        ["#{API}/tickets#assign", %w[ticket.assign]],
        ["#{A}/ticket_merges#merge", %w[ticket.merge]],
        ["#{API}/tickets#destroy", %w[ticket.delete]],
        ["#{STAFF}/tickets#apply_macro", %w[macro.view ticket.edit]],
        ["#{API}/tickets#apply_macro", %w[macro.view ticket.edit]],
        # Bulk: per action, see required_for.
        ["#{STAFF}/bulk_actions#create", VIEW],

        ["#{STAFF}/tickets#reply", %w[reply.create]],
        ["#{API}/tickets#reply", %w[reply.create]],
        ["#{STAFF}/tickets#note", %w[reply.create_internal]],
        ["#{A}/side_conversations#*", %w[reply.create]],

        ["#{A}/saved_views#*", VIEW],

        # ---- Live chat --------------------------------------------------------
        ["#{A}/chat\#{index,queue}", VIEW],
        ["#{A}/chat#*", %w[reply.create]],

        # ---- Reports ------------------------------------------------------------
        ["#{A}/advanced_reports#export", %w[report.export]],
        ["#{A}/{reports,advanced_reports}#*", %w[report.view]],

        # ---- Knowledge base ------------------------------------------------------
        ["#{A}/articles#index", %w[kb.view]],
        ["#{A}/articles\#{new,create}", %w[kb.create]],
        ["#{A}/articles\#{edit,update}", %w[kb.edit]],
        ["#{A}/articles#destroy", %w[kb.delete]],
        ["#{A}/kb_categories#index", %w[kb.view]],
        ["#{A}/kb_categories\#{create,update}", %w[kb.edit]],
        ["#{A}/kb_categories#destroy", %w[kb.delete]],

        # ---- Departments -----------------------------------------------------------
        ["#{A}/departments\#{index,show}", %w[department.view]],
        ["#{A}/departments\#{new,create}", %w[department.create]],
        ["#{A}/departments\#{edit,update}", %w[department.edit]],
        ["#{A}/departments#destroy", %w[department.delete]],

        # ---- Macros: anyone who may create one may save it; edits manage ------------
        ["#{A}/macros#index", %w[macro.view]],
        ["#{A}/macros#create", %w[macro.create]],
        ["#{A}/macros#*", %w[macro.manage]],

        # ---- Custom objects: schemas manage, records data -------------------------------
        ["#{A}/custom_objects#records", %w[custom_object.view]],
        ["#{A}/custom_objects\#{store_record,update_record,destroy_record}", %w[custom_object.data]],
        *resource('custom_objects', 'custom_object'),

        # ---- Users -------------------------------------------------------------------------
        ["#{A}/users#index", %w[user.view]],
        ["#{A}/users#update_role", %w[user.manage]],
        ["#{A}/users#update_roles", %w[role.manage]],
        ["#{A}/audit_logs#index", %w[audit.view]],

        # ---- Admin resources: reads => *.view, the rest => *.manage -------------------
        *resource('sla_policies', 'sla'),
        *resource('business_hours', 'sla'),
        *resource('escalation_rules', 'escalation'),
        *resource('automations', 'automation'),
        *resource('workflows', 'automation', reads: %w[index show logs]),
        *resource('tags', 'tag'),
        *resource('custom_fields', 'custom_field'),
        *resource('statuses', 'settings'),
        *resource('roles', 'role'),
        *resource('skills', 'user'),
        *resource('capacity', 'user'),
        *resource('webhooks', 'webhook', reads: %w[index show deliveries]),
        *resource('api_tokens', 'api_token'),
        *resource('plugins', 'plugin'),
        *resource('canned_responses', 'macro'),

        # ---- Settings ------------------------------------------------------------------------
        ["#{A}/imports#*", %w[settings.manage]],
        ["#{A}/settings\#{index,sso}", %w[settings.view]],
        ["#{A}/settings#*", %w[settings.manage]],
        ["#{A}/{csat_settings,data_retention,email_settings,public_tickets_settings,database_connection}#show",
         %w[settings.view]],
        ["#{A}/{csat_settings,data_retention,email_settings,public_tickets_settings,database_connection}#*",
         %w[settings.manage]],

        # ---- Newsletters (ADR 2026-05-19-newsletter-system) ---------------------------------
        ["#{A}/newsletter{s,_lists,_templates,_settings}#*", %w[newsletters.manage]]
      ].freeze

      FLAGS = File::FNM_EXTGLOB

      module_function

      # The slugs the action needs before looking at the request, or nil when unmapped.
      def lookup(controller_path, action)
        key = "#{controller_path}##{action}"
        MAP.each do |pattern, slugs|
          return slugs.dup if File.fnmatch?(pattern, key, FLAGS)
        end
        nil
      end

      def mapped?(controller_path, action)
        !lookup(controller_path, action).nil?
      end

      # The slugs a request needs, or nil when its action is not mapped (the
      # caller refuses it). Body-decided actions are checked per action: a
      # status change to resolved/closed/reopened also needs ticket.close, a
      # bulk action needs its own permission, and an internal API reply needs
      # reply.create_internal.
      def required_for(controller_path, action, params, bulk_action: nil)
        required = lookup(controller_path, action)
        return nil if required.nil?

        key = "#{controller_path}##{action}"
        if File.fnmatch?("#{STAFF}/bulk_actions#create", key, FLAGS)
          bulk = bulk_action.to_s
          required += BULK_ACTIONS.fetch(bulk, [])
          required += closing(params[:value]) if bulk == 'status'
        elsif key == "#{API}/tickets#reply" && [true, 'true', '1'].include?(params[:is_internal_note])
          required = %w[reply.create_internal]
        elsif required.include?('ticket.edit') && params.key?(:status)
          required += closing(params[:status])
        end

        required.uniq
      end

      def closing(status)
        CLOSING_STATUSES.include?(status.to_s) ? %w[ticket.close] : []
      end
    end
  end
end
