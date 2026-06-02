# frozen_string_literal: true

module Escalated
  class NewsletterUnsubscribeController < Escalated::ApplicationController
    include Escalated::NewsletterAccess

    skip_forgery_protection only: :store
    before_action :ensure_newsletters_enabled!

    def show
      delivery = find_delivery
      render 'escalated/newsletters/unsubscribe', locals: {
        token: params[:token],
        email: delivery&.email_at_send,
        confirmed: false
      }
    end

    def store
      return render plain: 'Too Many Requests', status: :too_many_requests unless throttle_unsubscribe!

      delivery = find_delivery
      delivery&.contact&.update!(marketing_opt_out_at: Time.current)

      render 'escalated/newsletters/unsubscribe', locals: {
        token: params[:token],
        email: delivery&.email_at_send,
        confirmed: true
      }
    end

    private

    def find_delivery
      Escalated::NewsletterDelivery.includes(:contact).find_by(tracking_token: params[:token])
    end

    def throttle_unsubscribe!
      key = "escalated.newsletter.unsubscribe.#{request.remote_ip}.#{Time.current.to_i / 60}"
      self.class.unsubscribe_counters[key] = self.class.unsubscribe_counters[key].to_i + 1
      self.class.unsubscribe_counters[key] <= 60
    end

    def self.unsubscribe_counters
      @unsubscribe_counters ||= {}
    end
  end
end
