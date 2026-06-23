# frozen_string_literal: true

require 'base64'

module Escalated
  class NewsletterTrackingController < Escalated::ApplicationController
    include Escalated::NewsletterAccess

    PIXEL_BYTES = Base64.decode64(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8//8/AwAF/gL+3MxZ5wAAAABJRU5ErkJggg=='
    ).freeze

    before_action :ensure_newsletters_enabled!

    def open
      token = params[:token].to_s.sub(/\.(gif|png|jpg)\z/i, '')
      Escalated::Newsletter::Tracker.new.record_open(token)

      render plain: PIXEL_BYTES, status: :ok, content_type: 'image/png',
             headers: { 'Cache-Control' => 'private, no-store, max-age=0' }
    end

    def click
      decoded = decode_destination(params[:u].to_s)
      return render plain: 'Bad request', status: :bad_request unless decoded

      Escalated::Newsletter::Tracker.new.record_click(params[:token], decoded)
      redirect_to decoded, allow_other_host: true
    end

    private

    def decode_destination(encoded)
      decoded = Base64.urlsafe_decode64(encoded)
      uri = URI.parse(decoded)
      return nil unless %w[http https].include?(uri.scheme.to_s.downcase)

      decoded
    rescue ArgumentError, URI::InvalidURIError
      nil
    end
  end
end
