# frozen_string_literal: true

require 'rails_helper'

# Escalated::ApplicationController runs every method named in
# configuration.middleware -- [:authenticate_user!] by default -- before each
# action. On a host with Devise (or anything shaped like it) that method exists
# on every controller and sends a signed-out visitor to the login page.
#
# That is right for the agent, admin and customer screens and wrong for the
# endpoints nobody signs in to: a mail provider posting inbound email, the
# embeddable widget, guest tickets, and the newsletter links in a recipient's
# inbox. The dummy app defines no authenticate_user!, so the suite never saw it.
RSpec.describe 'Public endpoints on a host with a login filter', type: :request do
  before do
    ActionController::Base.class_eval do
      def authenticate_user!
        redirect_to '/users/sign_in'
      end
    end

    allow(Escalated.configuration).to receive_messages(
      notification_channels: [],
      inbound_email_enabled: true,
      inbound_email_adapter: :mailgun,
      enable_newsletters?: true
    )
  end

  after do
    ActionController::Base.send(:remove_method, :authenticate_user!)
  end

  describe 'endpoints that must not ask anyone to sign in' do
    it 'lets a mail provider post inbound email' do
      post '/support/inbound/mailgun', params: { recipient: 'support@example.test' }

      expect(response).not_to be_redirect
      expect(response.media_type).to eq('application/json')
    end

    it 'serves the newsletter open pixel' do
      get '/escalated/n/o/some-token'

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('image/png')
    end

    it 'serves the newsletter unsubscribe page' do
      get '/escalated/n/u/some-token'

      expect(response).to have_http_status(:ok)
    end

    it 'serves the newsletter view-in-browser page' do
      get '/escalated/n/v/some-token'

      expect(response).to have_http_status(:ok)
    end

    it 'serves the widget config' do
      Escalated::EscalatedSetting.set('widget_enabled', 'true')

      get '/support/widget/config'

      expect(response).to have_http_status(:ok)
    end

    it 'serves widget chat availability' do
      get '/support/widget/chat/availability'

      expect(response).to have_http_status(:ok)
    end

    it 'serves the guest ticket form' do
      allow(Escalated::EscalatedSetting).to receive(:guest_tickets_enabled?).and_return(true)

      get '/support/guest/create'

      expect(response).to have_http_status(:ok)
    end

    # Plugin webhook routes are drawn only when the Node runtime boots, which
    # the suite does not do, so this one is checked on the controller itself.
    it 'does not run the host login filter on any public controller' do
      [
        Escalated::InboundController,
        Escalated::WidgetController,
        Escalated::WidgetChatController,
        Escalated::Guest::TicketsController,
        Escalated::NewsletterTrackingController,
        Escalated::NewsletterUnsubscribeController,
        Escalated::NewsletterViewInBrowserController,
        Escalated::Plugins::WebhooksController
      ].each do |controller|
        filters = controller._process_action_callbacks.select { |cb| cb.kind == :before }.map(&:filter)

        expect(filters).not_to include(:apply_middleware), "#{controller} still runs the host login filter"
      end
    end
  end

  describe 'screens that still require a signed-in user' do
    it 'sends a signed-out visitor from the admin screens to the host login' do
      get '/support/admin/tags'

      expect(response).to redirect_to('/users/sign_in')
    end

    it 'sends a signed-out visitor from the agent screens to the host login' do
      get '/support/agent'

      expect(response).to redirect_to('/users/sign_in')
    end

    it 'sends a signed-out visitor from the customer screens to the host login' do
      get '/support/customer/tickets'

      expect(response).to redirect_to('/users/sign_in')
    end

    it 'keeps plugin data endpoints behind the host login' do
      filters = Escalated::Plugins::EndpointsController._process_action_callbacks.map(&:filter)

      expect(filters).to include(:apply_middleware)
    end
  end

  # A host that authenticates some other way need not define current_user at
  # all. The shared Inertia props are built before every action, the JSON and
  # pixel responses included, and called it unguarded.
  describe 'on a host that defines no current_user' do
    around do |example|
      Escalated::ApplicationController.send(:remove_method, :current_user)
      example.run
    ensure
      Escalated::ApplicationController.class_eval do
        def current_user
          nil
        end
      end
    end

    it 'still serves the newsletter open pixel' do
      get '/escalated/n/o/some-token'

      expect(response).to have_http_status(:ok)
    end

    it 'still accepts inbound mail' do
      post '/support/inbound/mailgun', params: { recipient: 'support@example.test' }

      expect(response).not_to be_redirect
      expect(response.media_type).to eq('application/json')
    end
  end
end
