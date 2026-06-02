# frozen_string_literal: true

module Escalated
  class NewsletterViewInBrowserController < Escalated::ApplicationController
    include Escalated::NewsletterAccess

    UNAVAILABLE_HTML = '<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Email unavailable</title></head><body><p>This email is no longer available.</p></body></html>'

    before_action :ensure_newsletters_enabled!

    def show
      delivery = Escalated::NewsletterDelivery.includes(:contact, newsletter: :template)
                                              .find_by(tracking_token: params[:token])
      html = delivery ? Escalated::Newsletter::Renderer.new.render(delivery) : UNAVAILABLE_HTML

      render html: html.html_safe, status: :ok, content_type: 'text/html'
    end
  end
end
