# frozen_string_literal: true

require 'securerandom'

module Escalated
  module Newsletter
    # Plans a Newsletter for sending: snapshots the recipient set, applies
    # opt-out and bounce-suppression filters, and inserts one delivery row
    # per surviving contact with a fresh tracking token.
    class Planner
      def initialize(segments: ContactSegmentResolver.new,
                     bounces: BounceSuppressionStore.new)
        @segments = segments
        @bounces = bounces
      end

      def plan(newsletter)
        newsletter.update!(status: 'sending')

        contact_ids = @segments.resolve_sendable(newsletter.target_list)
        if contact_ids.empty?
          newsletter.update!(summary_total: 0)
          return
        end

        contacts = Escalated::Contact.where(id: contact_ids).select(:id, :email).to_a
        sendable_set = @bounces.filter_sendable(contacts.map(&:email)).map(&:downcase).to_set

        rows = []
        contacts.each do |contact|
          next unless sendable_set.include?(contact.email.downcase)

          rows << {
            newsletter_id: newsletter.id,
            contact_id: contact.id,
            email_at_send: contact.email,
            status: 'pending',
            tracking_token: SecureRandom.hex(20),
            attempt_count: 0,
            is_test: false,
            created_at: Time.current,
          }
        end

        rows.each_slice(500) do |slice|
          Escalated::NewsletterDelivery.insert_all(slice) if slice.any?
        end

        newsletter.update!(summary_total: rows.length)
      end
    end
  end
end
