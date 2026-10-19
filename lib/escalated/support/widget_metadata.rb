# frozen_string_literal: true

require 'uri'

module Escalated
  module Support
    # Host parameters an embedding page sends with a widget ticket or chat
    # (order number, plan, account id, the page URL, ...). They come from the
    # visitor's browser, so only a flat map of short scalar values is kept.
    module WidgetMetadata
      MAX_KEYS = 50
      MAX_ENTRIES = 25
      MAX_VALUE_LENGTH = 500
      MAX_URL_LENGTH = 2048
      KEY = /\A[A-Za-z0-9_.:-]{1,64}\z/

      module_function

      # True when metadata was sent but is not an object, or has more keys than
      # the request may carry at all.
      def invalid?(raw)
        return false if raw.nil?

        hash = to_hash(raw)
        hash.nil? || hash.size > MAX_KEYS
      end

      # The values worth keeping, plus `embedded_on` set from the request's
      # allowed Origin (never from the page). nil when nothing is left.
      def sanitize(raw, origin:)
        clean = {}
        (to_hash(raw) || {}).each do |key, value|
          break if clean.size >= MAX_ENTRIES
          next unless key.is_a?(String) && KEY.match?(key)

          value = scalar(value)
          clean[key] = value unless value.nil?
        end

        clean.delete('page_url') if clean.key?('page_url') && !web_url?(clean['page_url'])
        clean.delete('embedded_on')
        clean['embedded_on'] = origin if origin.is_a?(String)

        clean.empty? ? nil : clean
      end

      def to_hash(raw)
        raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
        raw.is_a?(Hash) ? raw.transform_keys(&:to_s) : nil
      end

      def scalar(value)
        case value
        when String then value.strip[0, MAX_VALUE_LENGTH]
        when Integer, Float, true, false then value
        end
      end

      def web_url?(value)
        return false unless value.is_a?(String) && value.length <= MAX_URL_LENGTH

        uri = URI.parse(value)
        uri.is_a?(URI::HTTP) && uri.host.present?
      rescue URI::Error
        false
      end
    end
  end
end
