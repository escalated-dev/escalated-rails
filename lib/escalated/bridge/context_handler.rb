module Escalated
  module Bridge
    # Handles ctx.* callbacks coming from the plugin runtime.
    #
    # The plugin runtime sends JSON-RPC requests back to the host when plugin
    # code calls ctx.tickets.find(), ctx.config.all(), ctx.store.query(), etc.
    # This class translates those calls into native ActiveRecord operations and
    # returns the result.
    #
    # ctx.* callbacks are synchronous from the plugin's perspective: the plugin
    # awaits the promise and the host blocks the JSON-RPC read loop until the
    # ActiveRecord operation completes, then sends back the JSON-RPC response.
    class ContextHandler
      # The plugin name that is currently executing (set before each dispatch).
      attr_writer :current_plugin

      # Reference back to the bridge for ctx.emit support.
      attr_writer :bridge

      def initialize
        @current_plugin = ""
        @bridge         = nil
      end

      # Dispatch a ctx.* method call from the runtime to the appropriate handler.
      #
      # @param method [String]  e.g. "ctx.tickets.find"
      # @param params [Hash]
      # @return [Object]
      def call(method, params)
        case method
        # Config
        when "ctx.config.all"    then config_all(params)
        when "ctx.config.get"    then config_get(params)
        when "ctx.config.set"    then config_set(params)

        # Store
        when "ctx.store.get"     then store_get(params)
        when "ctx.store.set"     then store_set(params)
        when "ctx.store.query"   then store_query(params)
        when "ctx.store.insert"  then store_insert(params)
        when "ctx.store.update"  then store_update(params)
        when "ctx.store.delete"  then store_delete(params)

        # Tickets
        when "ctx.tickets.find"   then tickets_find(params)
        when "ctx.tickets.query"  then tickets_query(params)
        when "ctx.tickets.create" then tickets_create(params)
        when "ctx.tickets.update" then tickets_update(params)

        # Replies
        when "ctx.replies.find"   then replies_find(params)
        when "ctx.replies.query"  then replies_query(params)
        when "ctx.replies.create" then replies_create(params)

        # Contacts (users)
        when "ctx.contacts.find"        then contacts_find(params)
        when "ctx.contacts.findByEmail" then contacts_find_by_email(params)
        when "ctx.contacts.create"      then contacts_create(params)

        # Tags
        when "ctx.tags.all"    then tags_all
        when "ctx.tags.create" then tags_create(params)

        # Departments
        when "ctx.departments.all"  then departments_all
        when "ctx.departments.find" then departments_find(params)

        # Agents
        when "ctx.agents.all"  then agents_all
        when "ctx.agents.find" then agents_find(params)

        # Broadcast
        when "ctx.broadcast.toChannel" then broadcast_to_channel(params)
        when "ctx.broadcast.toUser"    then broadcast_to_user(params)
        when "ctx.broadcast.toTicket"  then broadcast_to_ticket(params)

        # Misc
        when "ctx.emit"        then ctx_emit(params)
        when "ctx.log"         then ctx_log(params)
        when "ctx.currentUser" then current_user

        else
          raise "Unknown ctx method: #{method}"
        end
      end

      private

      # -----------------------------------------------------------------------
      # Config
      # -----------------------------------------------------------------------

      def config_all(params)
        plugin = params["plugin"] || @current_plugin
        get_plugin_config(plugin)
      end

      def config_get(params)
        plugin = params["plugin"] || @current_plugin
        key    = params["key"] or raise ArgumentError, "ctx.config.get requires key"
        get_plugin_config(plugin)[key]
      end

      def config_set(params)
        plugin = params["plugin"] || @current_plugin
        data   = params["data"] or raise ArgumentError, "ctx.config.set requires data"
        set_plugin_config(plugin, data)
        nil
      end

      def get_plugin_config(plugin)
        record = Escalated::PluginStoreRecord
          .where(plugin: plugin, collection: "__config__", key: "__config__")
          .first

        return {} unless record

        record.data.is_a?(Hash) ? record.data : {}
      end

      def set_plugin_config(plugin, data)
        existing = get_plugin_config(plugin)
        merged   = existing.merge(data)

        Escalated::PluginStoreRecord.find_or_initialize_by(
          plugin:     plugin,
          collection: "__config__",
          key:        "__config__"
        ).tap do |r|
          r.data = merged
          r.save!
        end
      end

      # -----------------------------------------------------------------------
      # Store
      # -----------------------------------------------------------------------

      def store_get(params)
        plugin     = params["plugin"] || @current_plugin
        collection = params["collection"] or raise ArgumentError, "ctx.store.get requires collection"
        key        = params["key"] or raise ArgumentError, "ctx.store.get requires key"

        record = Escalated::PluginStoreRecord
          .where(plugin: plugin, collection: collection, key: key)
          .first

        record&.data
      end

      def store_set(params)
        plugin     = params["plugin"] || @current_plugin
        collection = params["collection"] or raise ArgumentError, "ctx.store.set requires collection"
        key        = params["key"] or raise ArgumentError, "ctx.store.set requires key"
        value      = params["value"]

        Escalated::PluginStoreRecord.find_or_initialize_by(
          plugin:     plugin,
          collection: collection,
          key:        key
        ).tap do |r|
          r.data = value
          r.save!
        end

        nil
      end

      def store_query(params)
        plugin     = params["plugin"] || @current_plugin
        collection = params["collection"] or raise ArgumentError, "ctx.store.query requires collection"
        filter     = params["filter"] || {}
        options    = params["options"] || {}

        query = Escalated::PluginStoreRecord
          .where(plugin: plugin, collection: collection)

        filter.each do |field, condition|
          if condition.is_a?(Hash)
            condition.each do |op, val|
              query = apply_json_operator(query, field, op, val)
            end
          else
            # Simple equality — use JSON extract for nested data fields
            query = query.where("JSON_UNQUOTE(JSON_EXTRACT(data, '$.#{field}')) = ?", condition.to_s)
          end
        end

        if options["orderBy"]
          direction = options["order"] || "asc"
          safe_dir  = %w[asc desc].include?(direction.downcase) ? direction.downcase : "asc"
          query = query.order(
            Arel.sql("JSON_UNQUOTE(JSON_EXTRACT(data, '$.#{options["orderBy"]}')) #{safe_dir}")
          )
        end

        query = query.limit(options["limit"].to_i) if options["limit"]

        query.map { |r| { "_id" => r.id }.merge(r.data.is_a?(Hash) ? r.data : {}) }
      end

      def store_insert(params)
        plugin     = params["plugin"] || @current_plugin
        collection = params["collection"] or raise ArgumentError, "ctx.store.insert requires collection"
        data       = params["data"] or raise ArgumentError, "ctx.store.insert requires data"

        record = Escalated::PluginStoreRecord.create!(
          plugin:     plugin,
          collection: collection,
          key:        data["key"],
          data:       data
        )

        { "_id" => record.id }.merge(record.data.is_a?(Hash) ? record.data : {})
      end

      def store_update(params)
        plugin     = params["plugin"] || @current_plugin
        collection = params["collection"] or raise ArgumentError, "ctx.store.update requires collection"
        key        = params["key"] or raise ArgumentError, "ctx.store.update requires key"
        data       = params["data"] or raise ArgumentError, "ctx.store.update requires data"

        record = Escalated::PluginStoreRecord
          .where(plugin: plugin, collection: collection, key: key)
          .first!

        existing = record.data.is_a?(Hash) ? record.data : {}
        record.update!(data: existing.merge(data))

        { "_id" => record.id }.merge(record.data.is_a?(Hash) ? record.data : {})
      end

      def store_delete(params)
        plugin     = params["plugin"] || @current_plugin
        collection = params["collection"] or raise ArgumentError, "ctx.store.delete requires collection"
        key        = params["key"] or raise ArgumentError, "ctx.store.delete requires key"

        Escalated::PluginStoreRecord
          .where(plugin: plugin, collection: collection, key: key)
          .delete_all

        nil
      end

      # Apply a MongoDB-style query operator to an ActiveRecord relation.
      def apply_json_operator(query, field, op, value)
        extract = "JSON_UNQUOTE(JSON_EXTRACT(data, '$.#{field}'))"

        case op
        when "$gt"  then query.where("#{extract} > ?", value)
        when "$gte" then query.where("#{extract} >= ?", value)
        when "$lt"  then query.where("#{extract} < ?", value)
        when "$lte" then query.where("#{extract} <= ?", value)
        when "$ne"  then query.where("#{extract} != ?", value)
        when "$in"  then query.where("#{extract} IN (?)", Array(value))
        when "$nin" then query.where("#{extract} NOT IN (?)", Array(value))
        else
          raise ArgumentError, "Unsupported store query operator: #{op}"
        end
      end

      # -----------------------------------------------------------------------
      # Tickets
      # -----------------------------------------------------------------------

      def tickets_find(params)
        id     = params["id"] or raise ArgumentError, "ctx.tickets.find requires id"
        ticket = Escalated::Ticket.find_by(id: id)
        ticket&.as_json
      end

      def tickets_query(params)
        filter = params["filter"] || {}
        query  = Escalated::Ticket.all

        filter.each do |column, value|
          query = query.where(column => value)
        end

        query.map(&:as_json)
      end

      def tickets_create(params)
        data   = params["data"] or raise ArgumentError, "ctx.tickets.create requires data"
        ticket = Escalated::Ticket.create!(data)
        ticket.as_json
      end

      def tickets_update(params)
        id   = params["id"] or raise ArgumentError, "ctx.tickets.update requires id"
        data = params["data"] or raise ArgumentError, "ctx.tickets.update requires data"

        ticket = Escalated::Ticket.find(id)
        ticket.update!(data)
        ticket.reload.as_json
      end

      # -----------------------------------------------------------------------
      # Replies
      # -----------------------------------------------------------------------

      def replies_find(params)
        id    = params["id"] or raise ArgumentError, "ctx.replies.find requires id"
        reply = Escalated::Reply.find_by(id: id)
        reply&.as_json
      end

      def replies_query(params)
        filter = params["filter"] || {}
        query  = Escalated::Reply.all

        filter.each do |column, value|
          query = query.where(column => value)
        end

        query.map(&:as_json)
      end

      def replies_create(params)
        data  = params["data"] or raise ArgumentError, "ctx.replies.create requires data"
        reply = Escalated::Reply.create!(data)
        reply.as_json
      end

      # -----------------------------------------------------------------------
      # Contacts (users)
      # -----------------------------------------------------------------------

      def contacts_find(params)
        id    = params["id"] or raise ArgumentError, "ctx.contacts.find requires id"
        model = Escalated.configuration.user_model
        user  = model.find_by(id: id)
        user&.as_json
      end

      def contacts_find_by_email(params)
        email = params["email"] or raise ArgumentError, "ctx.contacts.findByEmail requires email"
        model = Escalated.configuration.user_model
        user  = model.find_by(email: email)
        user&.as_json
      end

      def contacts_create(params)
        data  = params["data"] or raise ArgumentError, "ctx.contacts.create requires data"
        model = Escalated.configuration.user_model
        user  = model.create!(data)
        user.as_json
      end

      # -----------------------------------------------------------------------
      # Tags
      # -----------------------------------------------------------------------

      def tags_all
        Escalated::Tag.all.map(&:as_json)
      end

      def tags_create(params)
        data = params["data"] or raise ArgumentError, "ctx.tags.create requires data"
        tag  = Escalated::Tag.create!(data)
        tag.as_json
      end

      # -----------------------------------------------------------------------
      # Departments
      # -----------------------------------------------------------------------

      def departments_all
        Escalated::Department.all.map(&:as_json)
      end

      def departments_find(params)
        id         = params["id"] or raise ArgumentError, "ctx.departments.find requires id"
        department = Escalated::Department.find_by(id: id)
        department&.as_json
      end

      # -----------------------------------------------------------------------
      # Agents
      # -----------------------------------------------------------------------

      def agents_all
        model = Escalated.configuration.user_model
        model.all.map(&:as_json)
      end

      def agents_find(params)
        id    = params["id"] or raise ArgumentError, "ctx.agents.find requires id"
        model = Escalated.configuration.user_model
        user  = model.find_by(id: id)
        user&.as_json
      end

      # -----------------------------------------------------------------------
      # Broadcast
      # -----------------------------------------------------------------------

      def broadcast_to_channel(params)
        channel = params["channel"] or raise ArgumentError, "ctx.broadcast.toChannel requires channel"
        event   = params["event"] or raise ArgumentError, "ctx.broadcast.toChannel requires event"
        data    = params["data"] || {}

        ActionCable.server.broadcast(channel, { event: event, data: data })
        nil
      end

      def broadcast_to_user(params)
        user_id = params["userId"] or raise ArgumentError, "ctx.broadcast.toUser requires userId"
        event   = params["event"] or raise ArgumentError, "ctx.broadcast.toUser requires event"
        data    = params["data"] || {}

        ActionCable.server.broadcast("private-user.#{user_id}", { event: event, data: data })
        nil
      end

      def broadcast_to_ticket(params)
        ticket_id = params["ticketId"] or raise ArgumentError, "ctx.broadcast.toTicket requires ticketId"
        event     = params["event"] or raise ArgumentError, "ctx.broadcast.toTicket requires event"
        data      = params["data"] || {}

        ActionCable.server.broadcast("private-ticket.#{ticket_id}", { event: event, data: data })
        nil
      end

      # -----------------------------------------------------------------------
      # Misc
      # -----------------------------------------------------------------------

      def ctx_emit(params)
        hook = params["hook"] or raise ArgumentError, "ctx.emit requires hook"
        data = params["data"] || {}

        @bridge&.dispatch_action(hook, data)
        nil
      end

      def ctx_log(params)
        level   = params["level"] || "info"
        message = params["message"] || ""
        context = (params["data"] || {}).merge("plugin" => (params["plugin"] || @current_plugin))

        case level
        when "debug"          then Rails.logger.debug("[Plugin] #{message} #{context}")
        when "warn", "warning" then Rails.logger.warn("[Plugin] #{message} #{context}")
        when "error"          then Rails.logger.error("[Plugin] #{message} #{context}")
        else                       Rails.logger.info("[Plugin] #{message} #{context}")
        end

        nil
      end

      def current_user
        # ActionController::Base.helpers has no request context here; this is
        # called during a background RPC cycle.  The plugin can pass a user_id
        # via the event payload instead.  Return nil as a safe default.
        nil
      end
    end
  end
end
