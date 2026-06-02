# frozen_string_literal: true

module Escalated
  class Newsletter
    # Pulls pending deliveries in batches, dispatches them via ActionMailer,
    # applies retry/backoff, finalizes completed newsletters, and auto-pauses
    # campaigns whose bounce rate exceeds the configured threshold.
    class Dispatcher
      def initialize(renderer: Renderer.new)
        @renderer = renderer
      end

      def dispatch_batch
        return unless Escalated.configuration.enable_newsletters?

        reclaim_stuck_rows

        batch_size = Escalated.configuration.newsletter_batch_size

        ids = Escalated::NewsletterDelivery.transaction do
          rows = Escalated::NewsletterDelivery
                 .pending
                 .order(:id)
                 .lock('FOR UPDATE')
                 .limit(batch_size)
                 .pluck(:id)
          if rows.any?
            Escalated::NewsletterDelivery.where(id: rows).update_all(
              status: 'queued',
              claimed_at: Time.current
            )
          end
          rows
        end

        ids.each do |id|
          delivery = Escalated::NewsletterDelivery.find_by(id: id)
          dispatch_one(delivery) if delivery
        end

        finalize_completed_newsletters
        check_auto_pause_across_active_newsletters
      end

      private

      def dispatch_one(delivery)
        delivery_full = Escalated::NewsletterDelivery
                        .includes(:contact, newsletter: :template)
                        .find(delivery.id)
        html = @renderer.render(delivery_full)

        host = URI.parse(Escalated.configuration.app_url || 'http://localhost').host || 'localhost'
        unsub = @renderer.unsubscribe_url(delivery_full)

        mailer.headers(
          'List-Unsubscribe' => "<#{unsub}>",
          'List-Unsubscribe-Post' => 'List-Unsubscribe=One-Click',
          'X-Escalated-Newsletter-Id' => delivery_full.newsletter_id.to_s,
          'Message-ID' => "<n-#{delivery_full.newsletter_id}-#{delivery_full.tracking_token}@#{host}>"
        )

        mailer.mail(
          to: delivery_full.email_at_send,
          from: format_from(delivery_full),
          reply_to: delivery_full.newsletter.reply_to.presence,
          subject: delivery_full.newsletter.subject,
          body: html,
          content_type: 'text/html'
        ).deliver_now

        delivery.update!(status: 'sent', sent_at: Time.current, claimed_at: nil)
        Escalated::Newsletter.where(id: delivery.newsletter_id).update_all('summary_sent = summary_sent + 1')
      rescue StandardError => e
        Rails.logger.warn("Newsletter delivery #{delivery.id} failed: #{e.message}")
        attempts = delivery.attempt_count + 1
        if attempts >= 3
          delivery.update!(status: 'failed', failure_reason: e.message,
                           attempt_count: attempts, claimed_at: nil)
        else
          delivery.update!(status: 'pending', attempt_count: attempts, claimed_at: nil)
        end
      end

      def mailer
        @mailer ||= ActionMailer::Base.new
      end

      def format_from(delivery)
        if delivery.newsletter.from_name.present?
          %("#{delivery.newsletter.from_name}" <#{delivery.newsletter.from_email}>)
        else
          delivery.newsletter.from_email
        end
      end

      def reclaim_stuck_rows
        cutoff = Escalated.configuration.newsletter_claim_timeout_minutes.minutes.ago
        Escalated::NewsletterDelivery
          .queued
          .where(claimed_at: ...cutoff)
          .update_all(status: 'pending', claimed_at: nil)
      end

      def finalize_completed_newsletters
        Escalated::Newsletter.where(status: 'sending').find_each do |n|
          remaining = Escalated::NewsletterDelivery.exists?(newsletter_id: n.id, status: %w[pending queued])
          n.update!(status: 'sent', sent_at: n.sent_at || Time.current) unless remaining
        end
      end

      def check_auto_pause_across_active_newsletters
        threshold = Escalated.configuration.newsletter_auto_pause_threshold
        rate = Escalated.configuration.newsletter_auto_pause_bounce_rate
        Escalated::Newsletter.where(status: 'sending').find_each do |n|
          total = Escalated::NewsletterDelivery.where(newsletter_id: n.id,
                                                      status: %w[
                                                        sent bounced complained failed
                                                      ]).count
          next if total < threshold

          bounced = Escalated::NewsletterDelivery.where(newsletter_id: n.id, status: 'bounced').count
          if total.positive? && bounced.to_f / total >= rate
            n.update!(status: 'paused')
            Rails.logger.warn("Newsletter #{n.id} auto-paused: #{bounced}/#{total} bounced")
          end
        end
      end
    end
  end
end
