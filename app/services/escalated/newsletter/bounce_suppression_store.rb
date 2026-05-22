# frozen_string_literal: true

module Escalated
  module Newsletter
    # Suppression store backed by the escalated_settings JSON value.
    # v1 holds the list in a single row keyed by 'newsletter.suppressed_emails'.
    class BounceSuppressionStore
      KEY = 'newsletter.suppressed_emails'

      def mark_bounced(email)
        mark(email)
      end

      def mark_complained(email)
        mark(email)
      end

      def bounced?(email)
        load_list.include?(email.to_s.downcase)
      end

      def filter_sendable(emails)
        suppressed = load_list.to_set
        emails.reject { |e| suppressed.include?(e.to_s.downcase) }
      end

      private

      def mark(email)
        lower = email.to_s.downcase
        list = load_list
        return if list.include?(lower)

        list << lower
        record = Escalated::EscalatedSettings.find_or_initialize_by(key: KEY)
        record.value = list.to_json
        record.type = 'json'
        record.group = 'newsletter'
        record.save!
      end

      def load_list
        record = Escalated::EscalatedSettings.find_by(key: KEY)
        return [] unless record&.value

        parsed = JSON.parse(record.value)
        parsed.is_a?(Array) ? parsed.map { |e| e.to_s.downcase } : []
      rescue JSON::ParserError
        []
      end
    end
  end
end
