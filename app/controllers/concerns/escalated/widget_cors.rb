# frozen_string_literal: true

module Escalated
  # CORS for the widget routes. Only origins listed in
  # Escalated.configuration.widget_allowed_origins or the
  # widget_allowed_origins setting get CORS headers, and such requests always
  # run as a guest. Same-origin requests, requests without an Origin and
  # requests from any other site pass through exactly as before.
  #
  # It runs as the first callback so the grant reaches every answer, including
  # the 403, 404, 422 and 429 ones rendered by later callbacks.
  module WidgetCors
    extend ActiveSupport::Concern

    ALLOW_METHODS = 'GET, POST, OPTIONS'
    ALLOW_HEADERS = 'Accept, Authorization, Content-Type, X-Requested-With'

    included do
      prepend_around_action :widget_cors
    end

    # OPTIONS {prefix}/widget/*path. Real preflights are answered by
    # widget_cors before this runs.
    def preflight
      head :no_content
    end

    private

    # A cross-site embed is anonymous: never act as whoever is signed in to the
    # host in the same browser. Covers escalated_current_user and the ticket
    # access actor, which both read current_user.
    def current_user
      return nil if widget_cross_origin

      defined?(super) ? super : nil
    end

    # The allowed embedding site this request came from, or nil.
    def widget_cross_origin
      @widget_cross_origin
    end

    def widget_cors
      origin = Escalated::Support::WidgetOrigins.cross_origin(request)
      allowed = origin.present? && Escalated::Support::WidgetOrigins.allows?(origin)

      return answer_widget_preflight(allowed ? origin : nil) if widget_preflight?
      return yield unless allowed

      @widget_cross_origin = origin
      begin
        response.headers['Access-Control-Allow-Origin'] = origin
        response.headers['Access-Control-Expose-Headers'] = 'Retry-After'
        yield
      ensure
        append_vary_origin
      end
    end

    def widget_preflight?
      request.options? && request.headers['Access-Control-Request-Method'].present?
    end

    def answer_widget_preflight(origin)
      if origin
        response.headers['Access-Control-Allow-Origin'] = origin
        response.headers['Access-Control-Allow-Methods'] = ALLOW_METHODS
        response.headers['Access-Control-Allow-Headers'] = ALLOW_HEADERS
        response.headers['Access-Control-Max-Age'] = Escalated.configuration.widget_preflight_max_age.to_i.to_s
      end
      append_vary_origin
      head :no_content
    end

    def append_vary_origin
      vary = response.headers['Vary'].to_s.split(',').map(&:strip).reject(&:empty?)
      vary << 'Origin' unless vary.include?('Origin')
      response.headers['Vary'] = vary.join(', ')
    end
  end
end
