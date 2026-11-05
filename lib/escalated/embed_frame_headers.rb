# frozen_string_literal: true

module Escalated
  # iframe mode of the embedded admin (ADR 2026-11-05-embeddable-admin): lets
  # the configured origins frame an embedded admin response and drops
  # X-Frame-Options from it, since frame-ancestors is the stricter,
  # allow-listed replacement. A Content-Security-Policy the host already sends
  # is kept; frame-ancestors is added to it as a second policy.
  #
  # The engine puts this at the top of the host's Rack stack, and only while
  # embedding is on, so it runs once the whole response is built: host
  # middleware that sets X-Frame-Options (secure_headers and the like) cannot
  # undo it. It changes only responses an embedded admin route marked (the
  # controller sets Support::EmbedConfig::FRAME_ENV); every other response
  # passes through untouched.
  class EmbedFrameHeaders
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)
      directive = env[Support::EmbedConfig::FRAME_ENV]
      return [status, headers, body] unless directive

      headers.each_key.select { |name| name.to_s.casecmp?('x-frame-options') }.each { |name| headers.delete(name) }
      csp_key = headers.each_key.find { |name| name.to_s.casecmp?('content-security-policy') }
      existing = csp_key && headers.delete(csp_key)
      policies = Array(existing).map(&:to_s).reject(&:empty?) << directive
      headers[csp_key || 'content-security-policy'] = policies.join(', ')

      [status, headers, body]
    end
  end
end
