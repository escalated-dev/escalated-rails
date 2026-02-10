module Escalated
  module ApiRateLimiting
    extend ActiveSupport::Concern

    private

    def enforce_rate_limit!
      key = rate_limit_key
      max_attempts = Escalated.configuration.api_rate_limit
      window = 60 # seconds

      cache_key = "escalated_api_rate:#{key}"
      current = Rails.cache.read(cache_key)

      if current.nil?
        Rails.cache.write(cache_key, { count: 1, reset_at: Time.current.to_i + window }, expires_in: window.seconds)
        set_rate_limit_headers(max_attempts, max_attempts - 1)
        return
      end

      if current[:count] >= max_attempts
        retry_after = [current[:reset_at] - Time.current.to_i, 1].max

        response.headers["Retry-After"] = retry_after.to_s
        response.headers["X-RateLimit-Limit"] = max_attempts.to_s
        response.headers["X-RateLimit-Remaining"] = "0"

        render json: {
          message: "Too many requests.",
          retry_after: retry_after
        }, status: :too_many_requests
        return
      end

      current[:count] += 1
      remaining_ttl = [current[:reset_at] - Time.current.to_i, 1].max
      Rails.cache.write(cache_key, current, expires_in: remaining_ttl.seconds)

      remaining = max_attempts - current[:count]
      set_rate_limit_headers(max_attempts, remaining)
    end

    def rate_limit_key
      if @current_api_token
        "token:#{@current_api_token.id}"
      else
        "ip:#{request.remote_ip}"
      end
    end

    def set_rate_limit_headers(limit, remaining)
      response.headers["X-RateLimit-Limit"] = limit.to_s
      response.headers["X-RateLimit-Remaining"] = [remaining, 0].max.to_s
    end
  end
end
