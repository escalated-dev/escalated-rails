# frozen_string_literal: true

module Escalated
  # Per-client-IP rate limit for the unauthenticated guest endpoints. Every
  # accepted guest ticket or reply writes rows and sends outbound mail, so an
  # uncapped endpoint lets anyone flood the helpdesk and the mail provider.
  #
  # Limits come from Escalated.configuration.guest_rate_limit (defaults: 5
  # ticket submissions and 10 replies per IP per minute, in separate buckets).
  # Over the limit the action is halted with 429 and Retry-After.
  #
  # The client IP is request.remote_ip. Behind a reverse proxy or load
  # balancer the host must set config.action_dispatch.trusted_proxies, or
  # every guest shares the proxy's address and one limit.
  #
  # Run the reply throttle before the guest-token lookup so requests with a
  # wrong token are counted too.
  module GuestThrottling
    extend ActiveSupport::Concern

    GUEST_THROTTLE_WINDOW = 60 # seconds

    private

    def throttle_guest_tickets!
      throttle_guest!(:ticket)
    end

    def throttle_guest_replies!
      throttle_guest!(:reply)
    end

    def throttle_guest!(scope)
      settings = Escalated.configuration.guest_rate_limit_settings
      return unless settings[:enabled]

      limit = settings[scope == :ticket ? :tickets_per_minute : :replies_per_minute].to_i
      store = settings[:cache_store] || Rails.cache

      # A fixed window aligned to the clock keeps the counter a single atomic
      # increment (the same primitive ActionController::RateLimiting uses).
      now = Time.current.to_f
      bucket = (now / GUEST_THROTTLE_WINDOW).floor
      key = "escalated:guest_throttle:#{scope}:#{request.remote_ip}:#{bucket}"
      hits = store.increment(key, 1, expires_in: (GUEST_THROTTLE_WINDOW + 5).seconds).to_i
      return if hits <= limit

      retry_after = [(((bucket + 1) * GUEST_THROTTLE_WINDOW) - now).ceil, 1].max
      response.headers['Retry-After'] = retry_after.to_s
      message = 'Too many requests. Please try again later.'

      if guest_throttle_json?
        render json: { error: message, retry_after: retry_after }, status: :too_many_requests
      else
        render plain: message, status: :too_many_requests
      end
    end

    # JSON endpoints (the widget) override this to always answer in JSON.
    def guest_throttle_json?
      request.format.json?
    end
  end
end
