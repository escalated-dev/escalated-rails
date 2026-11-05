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

    # Escalated's admin menu for the signed-in user, for a server-rendered
    # host layout (docs/embedding-admin.md): the items of
    # Escalated.admin_navigation, with the current page marked active.
    #
    #   <% escalated_admin_navigation.each do |item| %>
    #     <a href="<%= item[:url] %>"><%= item[:label] %></a>
    #   <% end %>
    def escalated_admin_navigation(user = :current)
      if user == :current
        user = if controller.respond_to?(:escalated_current_user, true)
                 controller.send(:escalated_current_user)
               elsif controller.respond_to?(:current_user, true)
                 controller.send(:current_user)
               end
      end
      Escalated.admin_navigation(user, request)
    end
  end
end
