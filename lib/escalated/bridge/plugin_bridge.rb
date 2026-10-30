# frozen_string_literal: true

require 'open3'

module Escalated
  module Bridge
    # Core bridge between Rails and the Node.js plugin runtime.
    #
    # Architecture
    # ────────────
    # The bridge spawns `node @escalated-dev/plugin-runtime` as a long-lived
    # child process.  Communication is bidirectional JSON-RPC 2.0 over stdio
    # (newline-delimited JSON).  The plugin runtime loads all installed SDK
    # plugins, handles their lifecycle, and routes hook dispatches from the host.
    #
    # The process is spawned LAZILY on the first hook dispatch, not at boot
    # time.  This avoids slowing down requests that never touch plugins (health
    # checks, etc.).
    #
    # Heartbeat & restart
    # ───────────────────
    # If the process crashes the next dispatch attempt detects the dead process
    # and triggers a restart with exponential backoff (up to 5 minutes).
    #
    # Queue depth
    # ───────────
    # Action hook messages are guarded by a counter up to 1 000 entries.
    # Beyond that new action hooks are dropped with a warning.  Filter hooks
    # return the unmodified value instead of being dropped.
    class PluginBridge
      PROTOCOL_VERSION  = '1.0'
      HOST_NAME         = 'rails'
      MAX_BACKOFF_SECS  = 300 # 5 minutes
      MAX_QUEUE_DEPTH   = 1_000

      TIMEOUT_ACTION    = 30
      TIMEOUT_FILTER    = 5
      TIMEOUT_ENDPOINT  = 30
      TIMEOUT_WEBHOOK   = 60
      TIMEOUT_HANDSHAKE = 15
      TIMEOUT_MANIFEST  = 15

      def initialize
        @stdin  = nil
        @stdout = nil
        @stderr = nil
        @pid    = nil
        @wait_thr = nil
        @rpc = nil

        @context_handler = ContextHandler.new
        @context_handler.bridge = self

        @manifests          = {}
        @booted             = false

        @restart_attempts = 0
        @last_restart_at  = 0
        @pending_action_count = 0

        @mutex = Mutex.new
      end

      # ======================================================================
      # Public API
      # ======================================================================

      # Boot the bridge: spawn the runtime, perform the handshake, retrieve
      # the plugin manifest, and register routes.
      #
      # Called from the engine initializer.  Safe to call when Node.js is not
      # installed — any exception is caught and logged.
      def boot
        return if @booted

        unless runtime_available?
          Rails.logger.info('[Escalated::Bridge] Node.js runtime not available — SDK plugins disabled')
          return
        end

        begin
          ensure_running
          fetch_manifests
          @booted = true
        rescue StandardError => e
          Rails.logger.warn("[Escalated::Bridge] Boot failed — SDK plugins disabled: #{e.message}")
          teardown
        end
      end

      # Dispatch a fire-and-forget action hook to SDK plugins.
      #
      # Blocks until the runtime acknowledges the action (or until the 30 s
      # timeout).  Errors are caught and logged — action hooks are best-effort.
      #
      # @param hook  [String]
      # @param event [Hash]
      def dispatch_action(hook, event)
        return unless ensure_alive

        if @pending_action_count >= MAX_QUEUE_DEPTH
          Rails.logger.warn("[Escalated::Bridge] Action queue full — dropping action '#{hook}'")
          return
        end

        # Only active plugins get hooks. The runtime loads every installed
        # plugin, so the active names go along for a runtime that gates on them.
        active = SdkPluginActivation.active_names(@manifests.keys)
        return if active.empty?

        @pending_action_count += 1

        begin
          @context_handler.current_plugin = '__host__'
          @rpc.call('action', { 'hook' => hook, 'event' => event, 'plugins' => active }, TIMEOUT_ACTION,
                    @context_handler)
        rescue StandardError => e
          Rails.logger.warn("[Escalated::Bridge] Action '#{hook}' failed: #{e.message}")
          handle_crash
        ensure
          @pending_action_count -= 1
        end
      end

      # Apply a filter hook through SDK plugins.
      #
      # Returns the filtered value, or the original +value+ on timeout/error.
      #
      # @param hook  [String]
      # @param value [Object]
      # @return [Object]
      def apply_filter(hook, value)
        return value unless ensure_alive

        active = SdkPluginActivation.active_names(@manifests.keys)
        return value if active.empty?

        begin
          @context_handler.current_plugin = '__host__'
          result = @rpc.call('filter', { 'hook' => hook, 'value' => value, 'plugins' => active }, TIMEOUT_FILTER,
                             @context_handler)
          result.nil? ? value : result
        rescue StandardError => e
          Rails.logger.warn("[Escalated::Bridge] Filter '#{hook}' failed — returning unmodified value: #{e.message}")
          handle_crash
          value
        end
      end

      # Run one of a plugin's cron schedules, as no user, within the action
      # timeout. Fire-and-forget: a failure is logged, never raised.
      #
      # @return [Boolean] whether the runtime ran it
      def cron(plugin, schedule)
        return false unless ensure_alive && SdkPluginActivation.active?(plugin)

        begin
          @context_handler.current_plugin = plugin
          @context_handler.acting_user = nil
          @rpc.call('cron', { 'plugin' => plugin, 'schedule' => schedule }, TIMEOUT_ACTION, @context_handler)
          true
        rescue StandardError => e
          Rails.logger.warn("[Escalated::Bridge] #{plugin} cron \"#{schedule}\" failed: #{e.message}")
          handle_crash
          false
        end
      end

      # Ask a widget's badge, as +user+ (ctx.currentUser is that user for the
      # call), within the filter timeout.
      #
      # @return [Numeric, String, nil] nil when the runtime fails or answers
      #   anything else
      def badge(plugin, component, user: nil)
        return nil unless ensure_alive && SdkPluginActivation.active?(plugin)

        begin
          @context_handler.current_plugin = plugin
          @context_handler.acting_user = user
          answer = @rpc.call('badge', { 'plugin' => plugin, 'component' => component }, TIMEOUT_FILTER,
                             @context_handler)
          answer.is_a?(Numeric) || answer.is_a?(String) ? answer : nil
        rescue StandardError => e
          Rails.logger.warn("[Escalated::Bridge] #{plugin} badge #{component} failed: #{e.message}")
          handle_crash
          nil
        ensure
          @context_handler.acting_user = nil
        end
      end

      # Call a plugin's data endpoint.
      #
      # @param plugin  [String]
      # @param method  [String]  HTTP verb
      # @param path    [String]
      # @param path    [String]  the manifest path (with :param segments)
      # @param request [Hash]    :body, :params (route params), :query, :headers
      # @return [Object]
      def call_endpoint(plugin, method, path, request = {})
        raise 'Plugin runtime is not available' unless ensure_alive
        raise ActionController::RoutingError, 'Not Found' unless SdkPluginActivation.active?(plugin)

        @context_handler.current_plugin = plugin

        @rpc.call(
          'endpoint',
          {
            'plugin' => plugin,
            'method' => method,
            'path' => path,
            'body' => request[:body],
            'params' => request[:params] || {},
            'query' => request[:query] || {},
            'headers' => request[:headers] || {}
          },
          TIMEOUT_ENDPOINT,
          @context_handler
        )
      end

      # Call a plugin's webhook handler.
      #
      # @param plugin  [String]
      # @param method  [String]  HTTP verb
      # @param path    [String]
      # @param body    [Hash]
      # @param headers [Hash]
      # @param transport [Hash]  :params (route params), :query
      # @return [Object]
      def call_webhook(plugin, method, path, body, headers, transport = {})
        raise 'Plugin runtime is not available' unless ensure_alive
        raise ActionController::RoutingError, 'Not Found' unless SdkPluginActivation.active?(plugin)

        @context_handler.current_plugin = plugin

        @rpc.call(
          'webhook',
          {
            'plugin' => plugin,
            'method' => method,
            'path' => path,
            'body' => body,
            'headers' => headers,
            'params' => transport[:params] || {},
            'query' => transport[:query] || {}
          },
          TIMEOUT_WEBHOOK,
          @context_handler
        )
      end

      # Tell the runtime a plugin was activated (`activate {plugin}`), which
      # calls its onActivate(ctx). A failure is logged, never raised: it does
      # not undo the activation.
      def activate(plugin)
        lifecycle('activate', plugin)
      end

      # Tell the runtime a plugin is being deactivated (`deactivate
      # {plugin}`), which calls its onDeactivate(ctx) while it is still active.
      def deactivate(plugin)
        lifecycle('deactivate', plugin)
      end

      # @return [Hash{String => Hash}]  plugin manifests (empty if not booted)
      attr_reader :manifests

      # @return [Boolean]
      def booted?
        @booted
      end

      # ======================================================================
      # Process lifecycle
      # ======================================================================

      private

      def lifecycle(method, plugin)
        return unless ensure_alive

        @context_handler.current_plugin = plugin
        @rpc.call(method, { 'plugin' => plugin }, TIMEOUT_ACTION, @context_handler)
      rescue StandardError => e
        Rails.logger.warn("[Escalated::Bridge] #{plugin} #{method} failed: #{e.message}")
        handle_crash
      end

      # Check that Node.js and the runtime package are available.
      def runtime_available?
        # Allow disabling via configuration
        return false if Escalated.configuration.respond_to?(:sdk_plugins_enabled) &&
                        Escalated.configuration.sdk_plugins_enabled == false

        node_version = begin
          `node --version 2>/dev/null`.strip
        rescue StandardError
          nil
        end
        node_version&.start_with?('v') || false
      end

      # Spawn the Node.js plugin runtime subprocess.
      def spawn_process
        command = if Escalated.configuration.respond_to?(:plugin_runtime_command) &&
                     Escalated.configuration.plugin_runtime_command
                    Escalated.configuration.plugin_runtime_command
                  else
                    'node node_modules/@escalated-dev/plugin-runtime/dist/index.js'
                  end

        cwd = if Escalated.configuration.respond_to?(:plugin_runtime_cwd) &&
                 Escalated.configuration.plugin_runtime_cwd
                Escalated.configuration.plugin_runtime_cwd
              else
                Rails.root.to_s
              end

        @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(command, chdir: cwd)
        @pid = @wait_thr.pid

        # Non-blocking reads so IO.select works correctly
        @stdout.sync = true
        @stdin.sync  = true

        @rpc = JsonRpcClient.new(@stdin, @stdout)

        Rails.logger.info("[Escalated::Bridge] Plugin runtime spawned (pid #{@pid})")
      end

      # Perform the handshake with the runtime.
      def handshake
        result = @rpc.call(
          'handshake',
          {
            'protocol_version' => PROTOCOL_VERSION,
            'host' => HOST_NAME,
            'host_version' => host_version
          },
          TIMEOUT_HANDSHAKE,
          @context_handler
        )

        unless result.is_a?(Hash) && result['compatible']
          runtime_ver  = result.is_a?(Hash) ? result['runtime_version']  || 'unknown' : 'unknown'
          protocol_ver = result.is_a?(Hash) ? result['protocol_version'] || 'unknown' : 'unknown'

          raise "Plugin runtime protocol mismatch: runtime speaks v#{protocol_ver} " \
                "(v#{runtime_ver}), host speaks v#{PROTOCOL_VERSION}"
        end

        Rails.logger.info(
          '[Escalated::Bridge] Handshake OK ' \
          "(runtime #{result['runtime_version']}, protocol #{result['protocol_version']})"
        )
      end

      # Fetch the plugin manifest from the runtime and store locally.
      def fetch_manifests
        result = @rpc.call('manifest', {}, TIMEOUT_MANIFEST, @context_handler)

        if result.is_a?(Array)
          result.each do |manifest|
            name = manifest['name']
            @manifests[name] = manifest if name
          end
        end

        Rails.logger.info("[Escalated::Bridge] Received manifests for: #{@manifests.keys.join(', ')}")

        SdkPluginActivation.record_installed(@manifests.keys)
        report_shared_slugs
      end

      # Two plugins with one slug would answer on each other's URLs: a
      # configuration error (plugin contract, Identity). Neither is served
      # (SdkPluginRoutes), and this names both.
      def report_shared_slugs
        @manifests.keys.group_by { |name| SdkPluginActivation.slug(name) }.each do |slug, names|
          next if names.size < 2

          Rails.logger.error("[Escalated::Bridge] Plugins #{names.join(' and ')} share the slug #{slug}; " \
                             'neither is served')
        end
      end

      # Ensure the runtime is running, spawning it lazily if needed.
      # Returns false if the runtime could not be started.
      def ensure_running
        return true if process_alive?

        # Enforce exponential backoff on repeated restarts
        if @restart_attempts.positive?
          backoff = [((2**(@restart_attempts - 1)) * 5).to_i, MAX_BACKOFF_SECS].min
          elapsed = Time.now.to_i - @last_restart_at

          if elapsed < backoff
            Rails.logger.debug { "[Escalated::Bridge] Waiting for backoff before restart (#{backoff - elapsed}s remaining)" }
            return false
          end
        end

        begin
          teardown
          spawn_process
          handshake
          fetch_manifests

          @restart_attempts = 0
          @booted           = true

          true
        rescue StandardError => e
          @restart_attempts += 1
          @last_restart_at  = Time.now.to_i

          Rails.logger.error(
            '[Escalated::Bridge] Failed to start plugin runtime ' \
            "(attempt #{@restart_attempts}): #{e.message}"
          )

          teardown
          false
        end
      end

      # Ensure the process is alive. Used before each RPC call.
      def ensure_alive
        return false unless runtime_available?
        return true  if process_alive?

        ensure_running
      end

      # Check whether the subprocess is still running.
      def process_alive?
        return false unless @pid && @wait_thr

        @wait_thr.alive?
      rescue StandardError
        false
      end

      # Handle a process crash: log it and clean up so the next call triggers
      # a restart via ensure_alive.
      def handle_crash
        return if process_alive?

        Rails.logger.warn('[Escalated::Bridge] Plugin runtime process has crashed — will restart on next dispatch')
        teardown
      end

      # Close the subprocess and clean up all handles.
      def teardown
        [@stdin, @stdout, @stderr].each do |io|
          next unless io

          begin
            io.close
          rescue StandardError
            nil
          end
        end

        if @wait_thr&.alive?
          begin
            Process.kill('TERM', @pid)
          rescue StandardError
            nil
          end
          @wait_thr.join(5)
          if @wait_thr.alive?
            begin
              Process.kill('KILL', @pid)
            rescue StandardError
              nil
            end
          end
        end
      rescue StandardError
        # best-effort teardown
      ensure
        @stdin    = nil
        @stdout   = nil
        @stderr   = nil
        @pid      = nil
        @wait_thr = nil
        @rpc      = nil
      end

      # Return the current gem version string.
      def host_version
        gemspec_path = File.expand_path('../../../../escalated.gemspec', __dir__)
        if File.exist?(gemspec_path)
          content = File.read(gemspec_path)
          match   = content.match(/\.version\s*=\s*["']([^"']+)["']/)
          match ? match[1] : '0.0.0'
        else
          '0.0.0'
        end
      end

      public

      # Clean up subprocess on GC/process shutdown.
      def shutdown
        teardown
      end
    end
  end
end
