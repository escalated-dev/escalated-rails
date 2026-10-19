# frozen_string_literal: true

require 'uri'

module Escalated
  module Support
    # Decides which other sites may embed the widget. The list is
    # Escalated.configuration.widget_allowed_origins (ESCALATED_WIDGET_ALLOWED_ORIGINS
    # by default) plus the admin setting `widget_allowed_origins`, one origin per
    # line or comma separated.
    #
    # Entries are bare origins, scheme://host[:port], http or https only.
    # https://*.example.com matches any subdomain of example.com at any depth,
    # but not example.com itself.
    module WidgetOrigins
      PATTERN = %r{\A(https?)://(\*\.)?([^/?#*]+?)/?\z}i

      module_function

      # The request's Origin when it names another site, or nil for same-origin
      # requests and requests without an Origin header.
      def cross_origin(request)
        origin = request.headers['Origin'].to_s
        return nil if origin.empty? || origin == 'null'

        origin = normalize(origin)
        return nil if origin.nil? || origin == normalize(request.base_url)

        origin
      end

      def allows?(origin)
        origin = normalize(origin.to_s)
        return false if origin.nil?

        configured.any? { |pattern| matches?(pattern, origin) }
      end

      # Every valid entry from the configuration and the admin setting.
      def configured
        entries = Array(Escalated.configuration.widget_allowed_origins)
        entries += Escalated::EscalatedSetting.get('widget_allowed_origins', '').to_s.split(/[\s,]+/)

        entries.filter_map { |entry| normalize_pattern(entry.to_s) }.uniq
      end

      # An admin-entered origin or "*." pattern in canonical form, or nil when
      # it is not a bare http(s) origin.
      def normalize_pattern(entry)
        match = PATTERN.match(entry.to_s.strip)
        return nil unless match

        origin = normalize("#{match[1].downcase}://#{match[3]}")
        return nil if origin.nil?

        match[2] ? origin.sub('://', '://*.') : origin
      end

      def matches?(pattern, origin)
        return pattern == origin unless pattern.include?('://*.')

        scheme, suffix = pattern.split('://*.', 2)
        return false unless origin.start_with?("#{scheme}://")

        host = origin.delete_prefix("#{scheme}://")
        host.end_with?(".#{suffix}") && host.length > suffix.length + 1
      end

      # scheme://host[:port], lowercased, default ports dropped.
      def normalize(origin)
        uri = URI.parse(origin.to_s.strip)
        return nil unless uri.is_a?(URI::HTTP) && uri.host.present?
        return nil if uri.userinfo || uri.query || uri.fragment || ['', '/'].exclude?(uri.path.to_s)

        scheme = uri.scheme.downcase
        host = uri.host.downcase
        uri.port == uri.default_port ? "#{scheme}://#{host}" : "#{scheme}://#{host}:#{uri.port}"
      rescue URI::Error
        nil
      end
    end
  end
end
