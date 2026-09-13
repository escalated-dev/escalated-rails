# frozen_string_literal: true

require 'ipaddr'
require 'socket'
require 'uri'

module Escalated
  module Support
    # Checks a URL that Escalated POSTs to on an admin's say-so -- a webhook, or
    # a workflow's send_webhook action -- so it cannot be aimed back into the
    # server's own network: loopback, the private ranges, link-local (where
    # cloud metadata services answer) and the like.
    #
    # A host that really does deliver to an internal address can set
    # config.allow_private_webhook_urls = true.
    module OutboundUrl
      class UnsafeUrl < StandardError; end

      BLOCKED_RANGES = %w[
        0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12
        192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4
        ::/96 64:ff9b::/96 fc00::/7 fe80::/10 fec0::/10 ff00::/8
      ].map { |range| IPAddr.new(range) }.freeze

      module_function

      # Why the URL may not be used, or nil when it may. With allow_unresolved a
      # host name that does not resolve passes: saving a webhook for a host that
      # is not in DNS yet proves nothing unsafe, and every delivery checks again.
      def problem(url, allow_unresolved: false)
        check(url, allow_unresolved: allow_unresolved).first
      end

      # The checked address to connect to. Connecting to it, rather than letting
      # Net::HTTP resolve the name a second time, keeps a DNS answer that changes
      # in between from slipping a private address through. Nil when private
      # addresses are allowed, leaving the name to Net::HTTP.
      def public_address!(url)
        reason, addresses = check(url, allow_unresolved: false)
        raise UnsafeUrl, "Webhook URL #{reason}" if reason

        addresses.first
      end

      def check(url, allow_unresolved:)
        uri = parse(url)
        return ['must be an http or https URL with a host', []] unless uri
        return ['must not include a username or password', []] if uri.userinfo
        return [nil, []] if Escalated.configuration.allow_private_webhook_urls

        addresses = addresses_for(uri.hostname)
        return [allow_unresolved ? nil : 'has a host name that could not be resolved', []] if addresses.empty?
        return ['points at a private, loopback or link-local address', []] if addresses.any? { |ip| blocked?(ip) }

        [nil, addresses]
      end

      def parse(url)
        uri = URI.parse(url.to_s.strip)
        uri if uri.is_a?(URI::HTTP) && uri.hostname.present?
      rescue URI::InvalidURIError
        nil
      end

      def addresses_for(host)
        [IPAddr.new(host).to_s]
      rescue IPAddr::InvalidAddressError
        resolve(host)
      end

      def resolve(host)
        Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address).uniq
      rescue SocketError
        []
      end

      # An address that cannot be parsed counts as blocked.
      def blocked?(address)
        ip = IPAddr.new(address)
        ip = ip.native if ip.ipv4_mapped?
        BLOCKED_RANGES.any? { |range| range.family == ip.family && range.include?(ip) }
      rescue IPAddr::InvalidAddressError
        true
      end
    end
  end
end
