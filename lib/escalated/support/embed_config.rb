# frozen_string_literal: true

require 'uri'

module Escalated
  module Support
    # Embedding the admin in the host's own admin panel
    # (ADR 2026-11-05-embeddable-admin). Optional and off by default: while
    # config.embed[:enabled] is false nothing here changes a route, a guard, a
    # prop, a layout or a header.
    #
    # Read from Escalated.configuration.embed (or config.embed_admin, which
    # writes it) when the routes are drawn, so a host sets it in
    # config/initializers/escalated.rb.
    module EmbedConfig
      MODES = %w[layout iframe].freeze
      DEFAULT_PREFIX = 'admin/support'

      # Set on the embedded admin routes (route defaults), and nowhere else.
      ROUTE_FLAG = :_escalated_embed

      # Rack env key: set by an embedded iframe-mode response for
      # Escalated::EmbedFrameHeaders, carrying the frame-ancestors directive.
      FRAME_ENV = 'escalated.embed.frame_ancestors'

      TRUE_VALUES = %w[1 true yes on].freeze

      module_function

      # The defaults, with the ESCALATED_EMBED* env vars.
      def defaults
        {
          enabled: TRUE_VALUES.include?(ENV.fetch('ESCALATED_EMBED', '').strip.downcase),
          mode: ENV.fetch('ESCALATED_EMBED_MODE', '').strip.presence || 'layout',
          prefix: ENV.fetch('ESCALATED_EMBED_PREFIX', '').strip.presence || DEFAULT_PREFIX,
          middleware: nil,
          replace_admin_gate: false,
          layout: nil,
          root_view: nil,
          frame_ancestors: ENV.fetch('ESCALATED_EMBED_FRAME_ANCESTORS', '').split(',').map(&:strip).reject(&:empty?)
        }
      end

      # config.embed with any key the host left out filled from the defaults.
      def settings
        defaults.merge((Escalated.configuration.embed || {}).to_h.symbolize_keys)
      end

      # On only with the screens on: the admin it moves is part of the UI.
      def enabled?
        settings[:enabled] == true && Escalated.configuration.ui_enabled?
      end

      def mode
        mode = settings[:mode].to_s
        MODES.include?(mode) ? mode : 'layout'
      end

      def iframe?
        mode == 'iframe'
      end

      # The host prefix the admin is mounted under while embedded, without slashes.
      def prefix
        prefix = settings[:prefix].to_s.gsub(%r{\A/+|/+\z}, '')
        prefix.empty? ? DEFAULT_PREFIX : prefix
      end

      # Escalated's own prefix, without slashes.
      def route_prefix
        Escalated.configuration.route_prefix.to_s.gsub(%r{\A/+|/+\z}, '')
      end

      def replace_admin_gate?
        settings[:replace_admin_gate] == true
      end

      def layout
        settings[:layout].presence&.to_s
      end

      def root_view
        settings[:root_view].presence&.to_s
      end

      # The host's guards for the embedded admin: before_action method names
      # or callables taking the controller. nil (the default): none of the
      # host's own, so the routes keep config.middleware, which every
      # Escalated screen runs today.
      def middleware
        configured = settings[:middleware]
        configured.nil? ? nil : Array(configured)
      end

      # Origins allowed to frame the admin in iframe mode: exact
      # scheme://host[:port] origins only. Wildcards, `*`, paths, credentials
      # and anything that is not http(s) are dropped.
      def frame_ancestors
        configured = settings[:frame_ancestors]
        configured = configured.split(',') if configured.is_a?(String)
        Array(configured).filter_map { |entry| origin(entry.to_s.strip) }.uniq
      end

      def frame_ancestors_directive
        (["frame-ancestors 'self'"] + frame_ancestors).join(' ')
      end

      # Refuses settings embed_admin cannot honour: an unknown mode, or a
      # replaced admin gate with nothing of the host's in its place.
      def validate!(settings)
        mode = settings[:mode].to_s
        unless MODES.include?(mode)
          raise ArgumentError, "Escalated embed mode must be 'layout' or 'iframe', got '#{mode}'."
        end

        validate_gate!(settings)
      end

      # Replacing the admin gate needs guards of the host's own: without them
      # any signed-in user would reach the admin. Checked again when the
      # routes are drawn, for settings written to config.embed directly.
      def validate_gate!(settings = self.settings)
        return unless settings[:replace_admin_gate] == true && Array(settings[:middleware]).empty?

        raise ArgumentError,
              'Escalated embed replace_admin_gate needs the host middleware that restricts the admin ' \
              '(middleware: [...]); without it any signed-in user would reach the admin.'
      end

      # Whether the request was routed to an embedded admin route.
      def embedded_request?(request)
        return false if request.nil? || !enabled?

        request.path_parameters.key?(ROUTE_FLAG)
      end

      # The `escalated.embed` shared prop. Only shared while embedding is on.
      def shared(request)
        embedded = embedded_request?(request)
        {
          enabled: embedded,
          mode: mode,
          layout: layout,
          route: embedded ? Escalated::RouteList.name_for(request.path, request.request_method) : nil,
          base_url: "/#{prefix}",
          allowed_origins: iframe? ? frame_ancestors : []
        }
      end

      def origin(value)
        return nil if value.empty? || value.include?('*')

        uri = URI.parse(value)
        return nil unless %w[http https].include?(uri.scheme&.downcase) && uri.host.present?
        return nil if uri.userinfo || uri.query || uri.fragment || ['', '/'].exclude?(uri.path.to_s)

        origin = "#{uri.scheme.downcase}://#{uri.host.downcase}"
        uri.port == uri.default_port ? origin : "#{origin}:#{uri.port}"
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
