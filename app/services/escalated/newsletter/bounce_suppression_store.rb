# frozen_string_literal: true

module Escalated
  class Newsletter
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
        # Model is EscalatedSetting (singular); the settings table only has
        # key/value columns (no type/group). Use the model's set/get API.
        Escalated::EscalatedSetting.set(KEY, list.to_json)
      end

      def load_list
        raw = Escalated::EscalatedSetting.get(KEY)
        return [] unless raw

        parsed = JSON.parse(raw)
        parsed.is_a?(Array) ? parsed.map { |e| e.to_s.downcase } : []
      rescue JSON::ParserError
        []
      end
    end
  end
end
