# frozen_string_literal: true

require 'digest'
require 'json'

module Escalated
  module Services
    # The agent panel's `inbox` and `queue` props (shared frontend
    # docs/agent-panel.md), as escalated-laravel's AgentInbox sends them.
    #
    # Every number is a count over the same filters the ticket list applies,
    # through Ticket's visibility scope, so it is what the agent would see by
    # opening that list. Rail counts (`counts`, `views`) are of unresolved,
    # unsnoozed tickets; `stats` are for the current queue.
    class AgentInbox
      SESSION_KEY = 'escalated_agent_inbox_queue'

      # Saved views beyond this many are not listed, so the counts stay bounded.
      MAX_SAVED_VIEWS = 50

      # Query keys that pick a page or an order, never which tickets are in a queue.
      PRESENTATION_KEYS = %w[page per_page view].freeze

      WORKSPACE_KEYS = %w[mine unassigned all].freeze

      def initialize(agent)
        @agent = agent
        @me = agent.id
      end

      # Translate `assigned=me` and `assigned_to=me` into the agent's id.
      def normalise_filters(filters)
        filters = filters.to_h.stringify_keys
        filters['assigned_to'] = @me if filters['assigned'] == 'me' || filters['assigned_to'] == 'me'
        filters.except('assigned')
      end

      # The queue a list request shows: { key:, title:, filters: }.
      def queue_for(filters)
        if filters['view'].present?
          view = views.find { |v| v[:id].to_s == filters['view'].to_s }
          return view_queue(view) if view
        end

        selection = comparable(filters)
        unless selection.empty?
          view = views.find { |v| v[:filters].present? && comparable(v[:filters]) == selection }
          return view_queue(view) if view
        end

        return workspace_queue('mine') if filters['assigned_to'].present? && filters['assigned_to'].to_s == @me.to_s
        return workspace_queue('unassigned') if Support::TicketListFilters.flag?(filters, 'unassigned')

        workspace_queue('all')
      end

      # The filters the list applies: the request's, over a view picked by id.
      def list_filters(filters, queue)
        return filters unless filters['view'].present? && queue[:key].start_with?('view:')

        queue[:filters].stringify_keys.merge(filters.except('view'))
      end

      # Remember the queue for the ticket page, which is opened from the list.
      def remember(session, queue)
        session[SESSION_KEY] = queue[:key]
      end

      # The queue last shown in the list, or All tickets.
      def recalled(session)
        key = session[SESSION_KEY]
        return workspace_queue('all') unless key.is_a?(String)

        if key.start_with?('view:')
          # The view may have been deleted or unshared since.
          view = views.find { |v| v[:id].to_s == key.delete_prefix('view:') }
          return view ? view_queue(view) : workspace_queue('all')
        end

        workspace_queue(key)
      end

      def queue_prop(queue)
        { key: queue[:key], title: queue[:title] }
      end

      # { inbox: ... }, or nothing in cloud mode: there the tickets live in the
      # hosted service, and counting the local table would show zeroes.
      def inbox_prop(queue)
        Escalated.configuration.cloud? ? {} : { inbox: summary(queue) }
      end

      def summary(queue)
        seconds = Escalated.configuration.agent_inbox_cache_seconds.to_i
        return build(queue) unless seconds.positive?

        digest = Digest::SHA1.hexdigest(JSON.generate([queue[:key], comparable(queue[:filters])]))
        key = "escalated/agent_inbox/#{@me}/#{I18n.locale}/#{digest}"
        Rails.cache.fetch(key, expires_in: seconds.seconds) { build(queue) }
      end

      # Built-in views, then the agent's own and shared saved views.
      def views
        @views ||= built_in_views + saved_views
      end

      private

      def build(queue)
        base = queue[:filters].stringify_keys
        {
          counts: {
            mine: count_open('assigned_to' => @me),
            unassigned: count_open('unassigned' => 1),
            all: count_open({})
          },
          # Of the same open tickets, those unread for this agent
          # (ADR 2026-11-05-agent-panel-data).
          unread: {
            mine: count_open_unread('assigned_to' => @me),
            unassigned: count_open_unread('unassigned' => 1),
            all: count_open_unread({})
          },
          views: views.map do |view|
            { id: view[:id], name: view[:name], count: count_open(view[:filters]), filters: view[:filters] }
          end,
          # Each stat is the list the tile opens: the queue plus the tile's filters.
          stats: {
            open: count(base.merge('status' => 'open')),
            urgent: count(base.merge('priority' => 'urgent', 'open' => 1)),
            sla_at_risk: count(base.merge('sla_at_risk' => 1)),
            resolved_today: count(base.merge('status' => 'resolved', 'resolved_today' => 1))
          }
        }
      end

      def built_in_views
        [
          ['urgent', { priority: 'urgent', open: 1 }],
          ['sla_at_risk', { sla_at_risk: 1 }],
          ['waiting_on_me', { assigned_to: @me, status: 'waiting_on_agent' }],
          ['waiting_on_customer', { assigned_to: @me, status: 'waiting_on_customer' }],
          ['recently_updated', { open: 1, updated_within_hours: 24, sort_by: 'updated_at' }]
        ].map do |id, filters|
          { id: id, name: I18n.t("escalated.agent_inbox.views.#{id}"), filters: filters }
        end
      end

      def saved_views
        Escalated::SavedView.accessible_by(@me)
                            .order(position: :asc, id: :asc)
                            .limit(MAX_SAVED_VIEWS)
                            .map do |view|
          filters = view.filters.is_a?(Hash) ? view.filters : {}
          { id: view.id, name: view.name, filters: normalise_filters(filters) }
        end
      end

      def view_queue(view)
        { key: "view:#{view[:id]}", title: view[:name], filters: view[:filters] }
      end

      def workspace_queue(key)
        key = 'all' unless WORKSPACE_KEYS.include?(key)
        filters = case key
                  when 'mine' then { 'assigned_to' => @me }
                  when 'unassigned' then { 'unassigned' => 1 }
                  else {}
                  end
        { key: key, title: I18n.t("escalated.agent_inbox.queues.#{key}"), filters: filters }
      end

      # Unresolved tickets, unless the filters ask for a status themselves.
      def count_open(filters)
        count(open_filters(filters))
      end

      # Of the same open tickets, those unread for this agent.
      def count_open_unread(filters)
        TicketReads.only_unread(scope_for(open_filters(filters)), @agent).count
      end

      def open_filters(filters)
        filters = filters.stringify_keys
        filters['status'].blank? ? filters.merge('open' => 1) : filters
      end

      def count(filters)
        scope_for(filters).count
      end

      def scope_for(filters)
        Support::TicketListFilters.apply(Escalated::Ticket.all, filters, @agent)
      end

      # Filters as strings, without empty values or order, for comparing a URL with a view.
      def comparable(filters)
        filters.to_h.stringify_keys.each_with_object({}) do |(key, value), clean|
          next if value.nil? || value == '' || value == false || PRESENTATION_KEYS.include?(key)

          clean[key] = if value.is_a?(Array)
                         value.map(&:to_s).sort.join(',')
                       else
                         value == true ? '1' : value.to_s
                       end
        end.sort.to_h
      end
    end
  end
end
