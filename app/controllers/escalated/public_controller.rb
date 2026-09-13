# frozen_string_literal: true

module Escalated
  # Base for the endpoints nobody signs in to: inbound mail from a provider, the
  # embeddable widget, guest tickets, newsletter links and plugin webhooks. Each
  # checks the request its own way (a provider signature, a guest or tracking
  # token, a rate limit), so the host login filters named in
  # configuration.middleware must not run -- they would send a mail provider or
  # a newsletter recipient to the host's sign-in page.
  class PublicController < ApplicationController
    skip_before_action :apply_middleware
  end
end
