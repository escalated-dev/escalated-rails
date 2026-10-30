# frozen_string_literal: true

module Escalated
  # View helper for the host's Inertia layout. Put it before the script that
  # mounts the app:
  #
  #   <%= escalated_route_helper_tag %>
  #   <%= vite_javascript_tag 'application' %>
  #
  # It installs Escalated::RouteList::ROUTE_HELPER, a Ziggy-compatible
  # window.route() over the `ziggy` prop, unless the host already has one.
  module RouteListHelper
    def escalated_route_helper_tag
      # With the host's CSP nonce, where it issues one.
      options = respond_to?(:content_security_policy_nonce) ? { nonce: true } : {}
      javascript_tag(Escalated::RouteList::ROUTE_HELPER, options)
    end
  end
end
