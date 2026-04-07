# frozen_string_literal: true

module Escalated
  # Controller concern that delegates page rendering to the configured
  # Escalated.ui_renderer.  Controllers call `render_page` instead of
  # `render inertia:` directly, which allows the UI layer to be swapped
  # or disabled entirely.
  module Renderable
    extend ActiveSupport::Concern

    private

    # Render a named UI page through the configured renderer.
    #
    # @param page   [String]  page/component identifier
    # @param props  [Hash]    data passed to the page
    # @param status [Symbol]  HTTP status (default :ok)
    def render_page(page, props = {}, status: :ok)
      Escalated.ui_renderer.render_page(self, page, props, status: status)
    end
  end
end
