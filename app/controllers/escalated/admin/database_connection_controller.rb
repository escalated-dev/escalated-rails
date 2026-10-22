# frozen_string_literal: true

module Escalated
  module Admin
    # Admin/Settings/DatabaseConnection: the database Escalated's own tables
    # live on.
    #
    # escalated-laravel lets an admin switch it from this screen. Here it is
    # `config.database_connection` (or the host's primary connection), which
    # Escalated::ApplicationRecord reads once, when the models load, so a web
    # form cannot change it without disagreeing with the deployed config. The
    # screen is therefore always the read-only form Laravel shows when the
    # connection is pinned by config: every configured connection, probed for
    # whether it is reachable and carries Escalated's tables, and a Test button
    # that probes one. A switch is refused, as Laravel refuses one when pinned.
    class DatabaseConnectionController < Escalated::ApplicationController
      include Escalated::InertiaForms

      before_action :require_admin!

      def show
        render_page 'Escalated/Admin/Settings/DatabaseConnection', {
          connections: configured.sort_by(&:name).map { |config| describe(config) },
          current: current_name,
          hostDefault: host_default_name,
          pinnedByConfig: true,
          tablePrefix: Escalated.configuration.table_prefix
        }
      end

      # Probe one connection and say what was found, without changing anything.
      def check
        config = configured.find { |c| c.name == params[:connection].to_s }
        unless config
          return redirect_back_with_form_errors(
            { 'connection' => "[#{params[:connection]}] is not configured in config/database.yml." },
            escalated.admin_settings_database_path
          )
        end

        result = describe(config)
        if result[:reachable] && result[:migrated]
          redirect_back_or_to(escalated.admin_settings_database_path,
                              notice: "[#{config.name}] is ready: #{result[:ticket_count]} tickets.")
        else
          redirect_back_or_to(escalated.admin_settings_database_path, alert: probe_problem(config, result))
        end
      end

      def update
        redirect_back_or_to(
          escalated.admin_settings_database_path,
          alert: 'The database connection is set in configuration (config.database_connection) and cannot be ' \
                 'changed from here.'
        )
      end

      private

      def configured
        @configured ||= ActiveRecord::Base.configurations.configs_for(env_name: Rails.env)
      end

      # The configured name, or nil for "the host's default", as Laravel sends it.
      def current_name
        spec = Escalated.configuration.database_connection
        spec = spec[:writing] || spec['writing'] if spec.is_a?(Hash)
        spec&.to_s
      end

      def host_default_name
        ActiveRecord::Base.connection_db_config&.name
      end

      def describe(config)
        description = {
          name: config.name,
          driver: config.adapter,
          database: database_label(config),
          is_current: config.name == (current_name || host_default_name),
          is_host_default: config.name == host_default_name,
          reachable: false,
          migrated: false,
          ticket_count: nil,
          error: nil
        }

        tickets = Escalated.table_name('tickets')
        probe(config) do |connection|
          description[:reachable] = true
          description[:migrated] = connection.data_source_exists?(tickets)
          if description[:migrated]
            description[:ticket_count] =
              connection.select_value("SELECT COUNT(*) FROM #{connection.quote_table_name(tickets)}").to_i
          end
        end

        description
      rescue StandardError => e
        # Shown to an admin choosing between databases. A connection that is
        # down renders as unusable, not as a 500 that takes the screen with it.
        description.merge(error: e.message)
      end

      # The connection Escalated is using is probed through its own pool (an
      # in-memory or already-open database is only visible there). Any other is
      # opened in a throwaway pool and closed again.
      def probe(config, &)
        live = Escalated::ApplicationRecord.connection_pool
        return live.with_connection(&) if live.db_config.name == config.name

        owner = "Escalated::DatabaseConnectionProbe::#{config.name}"
        handler = ActiveRecord::Base.connection_handler
        pool = handler.establish_connection(config, owner_name: owner)
        begin
          pool.with_connection(&)
        ensure
          handler.remove_connection_pool(owner, role: ActiveRecord.writing_role, shard: :default)
        end
      end

      def database_label(config)
        database = config.database.to_s
        return nil if database.empty?

        config.adapter.to_s.include?('sqlite') ? File.basename(database) : database
      end

      def probe_problem(config, result)
        if result[:error]
          "Could not connect to [#{config.name}]: #{result[:error]}"
        else
          "[#{config.name}] has no Escalated tables. Run the migrations against it before pointing Escalated at it."
        end
      end
    end
  end
end
