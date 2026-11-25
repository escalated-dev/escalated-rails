# frozen_string_literal: true

require 'rails_helper'

# The widget, guest portal and cloud webhook routes are public. An install that
# never uses one should not carry its routes: each is drawn only while its
# feature is on.
RSpec.describe 'Optional public routes', type: :request do
  def routed?(path, method: :get)
    Rails.application.routes.recognize_path(path, method: method)
    true
  rescue ActionController::RoutingError
    false
  end

  def redraw_with(**settings)
    previous = settings.keys.index_with { |key| Escalated.configuration.public_send(key) }
    settings.each { |key, value| Escalated.configuration.public_send(:"#{key}=", value) }
    Rails.application.reload_routes!
    yield
  ensure
    previous&.each { |key, value| Escalated.configuration.public_send(:"#{key}=", value) }
    Rails.application.reload_routes!
  end

  def widget_paths
    [
      ['/support/widget/config', :get],
      ['/support/widget/tickets', :post],
      ['/support/widget/embed.js', :get],
      ['/support/widget/chat/start', :post],
      ['/support/widget/config', :options]
    ]
  end

  def guest_paths
    [
      ['/support/guest/create', :get],
      ['/support/guest', :post],
      ['/support/guest/abc123', :get],
      ['/support/guest/verification', :post]
    ]
  end

  describe 'with the defaults' do
    it 'draws the widget and guest routes' do
      (widget_paths + guest_paths).each do |path, method|
        expect(routed?(path, method: method)).to be(true), "#{method.upcase} #{path} is not routed"
      end
    end

    it 'enables both switches' do
      config = Escalated::Configuration.new

      expect(config.widget_enabled?).to be(true)
      expect(config.guest_routes_enabled?).to be(true)
    end

    it 'does not draw the cloud webhook without a signing secret' do
      expect(Escalated.configuration.hosted_signing_secret).to be_blank
      expect(routed?('/support/cloud/webhook', method: :post)).to be(false)
    end
  end

  it 'draws no widget route while the widget is off' do
    redraw_with(widget_enabled: false) do
      widget_paths.each do |path, method|
        expect(routed?(path, method: method)).to be(false), "#{method.upcase} #{path} is still routed"
      end
      expect(routed?('/support/guest/create')).to be(true)
    end
  end

  it 'draws no guest route while the guest routes are off' do
    redraw_with(guest_routes_enabled: false) do
      guest_paths.each do |path, method|
        expect(routed?(path, method: method)).to be(false), "#{method.upcase} #{path} is still routed"
      end
      expect(routed?('/support/widget/config')).to be(true)
    end
  end

  it 'tells the frontend guest tickets are off while the guest routes are off' do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    Escalated::EscalatedSetting.set('guest_tickets_enabled', '1')
    user = create(:user, email: 'guest-routes-off@example.test')
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)

    get '/support/customer/tickets'
    expect(inertia_page.dig('props', 'escalated', 'guest_tickets_enabled')).to be(true)

    redraw_with(guest_routes_enabled: false) do
      get '/support/customer/tickets'
      expect(inertia_page.dig('props', 'escalated', 'guest_tickets_enabled')).to be(false)
    end
  end

  it 'draws the cloud webhook once the signing secret is set' do
    redraw_with(hosted_signing_secret: 'whsec_test') do
      expect(routed?('/support/cloud/webhook', method: :post)).to be(true)
    end
  end

  describe 'environment switches' do
    around do |example|
      saved = ENV.to_h.slice('ESCALATED_WIDGET_ENABLED', 'ESCALATED_GUEST_ROUTES')
      example.run
    ensure
      ENV.delete('ESCALATED_WIDGET_ENABLED')
      ENV.delete('ESCALATED_GUEST_ROUTES')
      ENV.update(saved)
    end

    it 'reads ESCALATED_WIDGET_ENABLED and ESCALATED_GUEST_ROUTES' do
      ENV['ESCALATED_WIDGET_ENABLED'] = 'false'
      ENV['ESCALATED_GUEST_ROUTES'] = '0'
      config = Escalated::Configuration.new

      expect(config.widget_enabled?).to be(false)
      expect(config.guest_routes_enabled?).to be(false)
    end

    it 'keeps them on for any other value' do
      ENV['ESCALATED_WIDGET_ENABLED'] = 'true'
      ENV['ESCALATED_GUEST_ROUTES'] = ''
      config = Escalated::Configuration.new

      expect(config.widget_enabled?).to be(true)
      expect(config.guest_routes_enabled?).to be(true)
    end
  end
end
