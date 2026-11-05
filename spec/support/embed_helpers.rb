# frozen_string_literal: true

# Stand-ins for a host application's own admin guards in the embedding specs
# (ADR 2026-11-05-embeddable-admin), and a switch that turns embedding on for
# one example group. Routes are drawn from the configuration, so turning it on
# or off redraws them.
module EmbedHelpers
  OWNER_EMAIL = 'owner@host.test'

  # Marks the response, proving the host's guard ran on the request.
  HOST_MARK = ->(controller) { controller.response.set_header('X-Host-Admin', '1') }

  # The host's authentication: nobody signed in, 401.
  HOST_AUTHENTICATE = lambda do |controller|
    controller.head(:unauthorized) unless controller.send(:escalated_current_user)
  end

  # A host admin gate: only owner@host.test gets through.
  HOST_OWNER_GATE = lambda do |controller|
    controller.head(:forbidden) unless controller.send(:escalated_current_user)&.email == OWNER_EMAIL
  end

  # A host-wide Rack middleware sending its own framing headers, as many apps
  # do (secure_headers and the like), to prove iframe mode overrides it only
  # where embedded.
  class HostFrameHeaders
    def initialize(app, csp: nil)
      @app = app
      @csp = csp
    end

    def call(env)
      status, headers, body = @app.call(env)
      headers['x-frame-options'] = 'DENY'
      headers['content-security-policy'] = @csp if @csp
      [status, headers, body]
    end
  end

  def self.layout_config
    {
      enabled: true,
      mode: 'layout',
      prefix: 'backoffice/helpdesk',
      middleware: [HOST_AUTHENTICATE, HOST_MARK],
      layout: 'Layouts/AdminLayout'
    }
  end

  module ClassMethods
    # Embeds the admin with +config+ (merged over layout_config) around every
    # example in the group, then restores the default and redraws the routes.
    def embed_admin_with(config = {})
      around do |example|
        previous = Escalated.configuration.embed
        Escalated.configuration.embed = EmbedHelpers.layout_config.merge(config)
        Rails.application.reload_routes!
        example.run
      ensure
        Escalated.configuration.embed = previous
        Rails.application.reload_routes!
      end
    end
  end

  def sign_in_as(user)
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)
  end
end

# A host guard by method name, as config.middleware names authenticate_user!.
Escalated::ApplicationController.class_eval do
  private

  def spec_host_guard!
    response.set_header('X-Host-Symbol', '1')
  end
end

RSpec.configure do |config|
  config.include EmbedHelpers, type: :request
  config.extend EmbedHelpers::ClassMethods, type: :request
end
