# frozen_string_literal: true

require 'digest'

module Escalated
  # Serves the standalone widget bundle (vendor/widget/escalated-widget.js,
  # built by @escalated-dev/escalated) so any site can load it with a <script>
  # tag pointing at this install.
  #
  # A plain ActionController::Base, not PublicController: it needs none of the
  # engine's callbacks, and Rails' cross-origin JavaScript check
  # (verify_same_origin_request) would refuse exactly the cross-site <script>
  # load this exists for.
  class WidgetScriptController < ActionController::Base # rubocop:disable Rails/ApplicationController
    BUNDLE = Escalated::Engine.root.join('vendor', 'widget', 'escalated-widget.js').to_s.freeze

    skip_forgery_protection

    def show
      return head :not_found unless File.file?(BUNDLE)

      etag = %("#{Digest::MD5.file(BUNDLE).hexdigest}")
      response.headers['ETag'] = etag
      response.headers['Cache-Control'] = 'public, max-age=3600'
      response.headers['X-Content-Type-Options'] = 'nosniff'
      response.headers['Cross-Origin-Resource-Policy'] = 'cross-origin'
      response.headers['Access-Control-Allow-Origin'] = '*'

      return head :not_modified if request.if_none_match_etags.include?(etag)

      render body: File.read(BUNDLE), content_type: 'application/javascript; charset=utf-8'
    end
  end
end
