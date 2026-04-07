# frozen_string_literal: true

module Escalated
  # Abstract base for rendering UI pages.
  #
  # The default implementation delegates to Inertia (via InertiaRenderer).
  # Host apps that disable the built-in Inertia UI can provide their own
  # renderer by assigning a custom object to Escalated.ui_renderer.
  #
  # Any renderer must respond to #render_page(controller, page, props, status:).
  module UiRenderer
    class Base
      # Render a named page with the given props.
      #
      # @param controller [ActionController::Base] the current controller instance
      # @param page       [String]  page/component identifier (e.g. "Escalated/Agent/Dashboard")
      # @param props      [Hash]    data to pass to the page
      # @param status     [Symbol]  HTTP status (default :ok)
      # @return [void]
      def render_page(controller, page, props = {}, status: :ok)
        raise NotImplementedError, "#{self.class}#render_page must be implemented"
      end
    end

    # Default renderer that delegates to the inertia-rails gem.
    class InertiaRenderer < Base
      def render_page(controller, page, props = {}, status: :ok)
        controller.render inertia: page, props: props, status: status
      end
    end
  end
end
