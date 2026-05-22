# frozen_string_literal: true

module Escalated
  module Newsletter
    # Applies tracking events (open, click, bounce, complaint) to delivery rows
    # idempotently. Bounces and complaints also update the suppression store.
    class Tracker
      def initialize(bounces: BounceSuppressionStore.new)
        @bounces = bounces
      end

      def record_open(token)
        delivery = find_by_token(token)
        return unless delivery
        return if terminal?(delivery)
        return if delivery.opened_at.present?

        delivery.update!(opened_at: Time.current)
        Escalated::Newsletter.where(id: delivery.newsletter_id)
                             .update_all('summary_opened = summary_opened + 1')
      end

      def record_click(token, _url)
        delivery = find_by_token(token)
        return unless delivery
        return if terminal?(delivery)

        first_click = delivery.clicks_count.to_i.zero?
        delivery.update!(clicks_count: delivery.clicks_count + 1,
                         last_clicked_at: Time.current)
        if delivery.opened_at.nil?
          delivery.update!(opened_at: Time.current)
          Escalated::Newsletter.where(id: delivery.newsletter_id)
                               .update_all('summary_opened = summary_opened + 1')
        end
        if first_click
          Escalated::Newsletter.where(id: delivery.newsletter_id)
                               .update_all('summary_clicked = summary_clicked + 1')
        end
      end

      def record_bounce(token, type, reason = nil)
        delivery = find_by_token(token)
        return unless delivery
        return unless type == 'hard'
        return if delivery.status == 'bounced'

        delivery.update!(status: 'bounced', bounce_reason: reason)
        Escalated::Newsletter.where(id: delivery.newsletter_id)
                             .update_all('summary_bounced = summary_bounced + 1')
        @bounces.mark_bounced(delivery.email_at_send)
      end

      def record_complaint(token)
        delivery = find_by_token(token)
        return unless delivery
        return if delivery.status == 'complained'

        delivery.update!(status: 'complained')
        Escalated::Newsletter.where(id: delivery.newsletter_id)
                             .update_all('summary_complained = summary_complained + 1')
        @bounces.mark_complained(delivery.email_at_send)
      end

      private

      def find_by_token(token)
        Escalated::NewsletterDelivery.find_by(tracking_token: token)
      end

      def terminal?(delivery)
        %w[bounced complained failed].include?(delivery.status)
      end
    end
  end
end
