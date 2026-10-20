# frozen_string_literal: true

require 'rails_helper'

# Embedding the widget on another site: CORS for the origins an admin lists,
# guest-only requests from them, host parameters (metadata) on tickets and
# chats, and the standalone embed.js bundle.
RSpec.describe 'Widget embedding on other sites', type: :request do
  let(:shop) { 'https://shop.example.com' }
  let(:ticket_params) do
    { name: 'Jane Doe', email: 'jane@example.com', subject: 'Where is my order?',
      description: 'It has not arrived yet.' }
  end

  before do
    Rails.cache.clear
    allow(Escalated.configuration).to receive_messages(notification_channels: [], widget_allowed_origins: [shop])
    Escalated::EscalatedSetting.set('widget_enabled', '1')
  end

  after { Rails.cache.clear }

  def preflight(path, origin)
    process :options, path, headers: {
      'Origin' => origin,
      'Access-Control-Request-Method' => 'POST',
      'Access-Control-Request-Headers' => 'content-type,authorization'
    }
  end

  def post_json(path, payload, origin: nil)
    headers = { 'CONTENT_TYPE' => 'application/json', 'ACCEPT' => 'application/json' }
    headers['Origin'] = origin if origin
    post path, params: payload.to_json, headers: headers
  end

  def created_ticket
    Escalated::Ticket.find_by!(reference: response.parsed_body['reference'])
  end

  describe 'CORS' do
    it 'answers a preflight from an allowed site' do
      preflight('/support/widget/tickets', shop)

      expect(response).to have_http_status(:no_content)
      expect(response.headers['Access-Control-Allow-Origin']).to eq(shop)
      expect(response.headers['Access-Control-Allow-Methods']).to eq('GET, POST, OPTIONS')
      expect(response.headers['Access-Control-Allow-Headers'])
        .to eq('Accept, Authorization, Content-Type, X-Requested-With')
      expect(response.headers['Access-Control-Max-Age']).to eq('600')
      expect(response.headers['Vary']).to include('Origin')
      expect(response.headers).not_to have_key('Access-Control-Allow-Credentials')
    end

    it 'answers a preflight for the chat routes too' do
      preflight('/support/widget/chat/start', shop)

      expect(response).to have_http_status(:no_content)
      expect(response.headers['Access-Control-Allow-Origin']).to eq(shop)
    end

    it 'gives no CORS grant to a site that is not allowed' do
      preflight('/support/widget/tickets', 'https://evil.example.net')
      expect(response).to have_http_status(:no_content)
      expect(response.headers).not_to have_key('Access-Control-Allow-Origin')

      get '/support/widget/config', headers: { 'Origin' => 'https://evil.example.net' }
      expect(response).to have_http_status(:ok)
      expect(response.headers).not_to have_key('Access-Control-Allow-Origin')
    end

    it 'adds the grant to answers for an allowed site' do
      get '/support/widget/config', headers: { 'Origin' => shop }

      expect(response).to have_http_status(:ok)
      expect(response.headers['Access-Control-Allow-Origin']).to eq(shop)
      expect(response.headers['Access-Control-Expose-Headers']).to eq('Retry-After')
      expect(response.headers['Vary']).to include('Origin')
      expect(response.headers).not_to have_key('Access-Control-Allow-Credentials')
    end

    it 'leaves same-origin requests and requests without an Origin alone' do
      get '/support/widget/config', headers: { 'Origin' => 'http://www.example.com' }
      expect(response.headers).not_to have_key('Access-Control-Allow-Origin')

      get '/support/widget/config'
      expect(response.headers).not_to have_key('Access-Control-Allow-Origin')
    end

    it 'reads allowed sites from the admin setting, including subdomain wildcards' do
      allow(Escalated.configuration).to receive(:widget_allowed_origins).and_return([])
      Escalated::EscalatedSetting.set('widget_allowed_origins', "https://*.brand.test\nhttp://localhost:5173")

      granted = lambda do |origin|
        get '/support/widget/config', headers: { 'Origin' => origin }
        response.headers['Access-Control-Allow-Origin']
      end

      expect(granted.call('https://help.brand.test')).to eq('https://help.brand.test')
      expect(granted.call('https://a.b.brand.test')).to eq('https://a.b.brand.test')
      expect(granted.call('http://localhost:5173')).to eq('http://localhost:5173')
      expect(granted.call('https://brand.test')).to be_nil
      expect(granted.call('http://help.brand.test')).to be_nil
      expect(granted.call('https://evilbrand.test')).to be_nil
      expect(granted.call('http://localhost:5174')).to be_nil
    end

    it 'adds the grant to error answers for an allowed site' do
      get '/support/widget/articles/missing', headers: { 'Origin' => shop }
      expect(response).to have_http_status(:not_found)
      expect(response.headers['Access-Control-Allow-Origin']).to eq(shop)

      Escalated::EscalatedSetting.set('widget_enabled', '0')
      get '/support/widget/config', headers: { 'Origin' => shop }
      expect(response).to have_http_status(:forbidden)
      expect(response.headers['Access-Control-Allow-Origin']).to eq(shop)
    end

    it 'adds the grant to validation answers for an allowed site' do
      post_json('/support/widget/tickets', { name: 'x' }, origin: shop)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.headers['Access-Control-Allow-Origin']).to eq(shop)
    end

    it 'adds the grant and exposes Retry-After on rate-limit answers' do
      allow(Escalated.configuration).to receive(:api_rate_limit).and_return(1)

      get '/support/widget/config', headers: { 'Origin' => shop }
      expect(response).to have_http_status(:ok)
      get '/support/widget/config', headers: { 'Origin' => shop }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers['Access-Control-Allow-Origin']).to eq(shop)
      expect(response.headers['Access-Control-Expose-Headers']).to include('Retry-After')
      expect(response.headers['Retry-After']).to be_present
    end
  end

  describe 'forgery protection' do
    around do |example|
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = original
    end

    it 'lets an allowed site create a ticket without a CSRF token' do
      post_json('/support/widget/tickets', ticket_params, origin: shop)

      expect(response).to have_http_status(:created)
      expect(response.headers['Access-Control-Allow-Origin']).to eq(shop)
      expect(Escalated::Ticket.where(subject: 'Where is my order?')).to exist
    end

    # Only an allowed embedding site skips CSRF (Laravel's WidgetCsrf). A
    # tokenless POST from anywhere else used to be accepted under
    # :null_session; it is refused now, and gets no CORS grant.
    ['https://evil.example.net', 'http://www.example.com', nil].each do |origin|
      it "refuses a tokenless POST from #{origin.inspect}, with no CORS grant" do
        post_json('/support/widget/tickets', ticket_params, origin: origin)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.headers).not_to have_key('Access-Control-Allow-Origin')
        expect(Escalated::Ticket.where(subject: 'Where is my order?')).not_to exist
      end
    end
  end

  describe 'guest forcing' do
    let(:agent) { create(:user, :agent) }
    let(:seen) { [] }

    # spec/rails_helper.rb stands in for the host's current_user on
    # Escalated::ApplicationController; sign the agent in there.
    before do
      signed_in = agent
      Escalated::ApplicationController.define_method(:current_user) { signed_in }
      allow(Escalated::Services::TicketService).to receive(:create_local).and_wrap_original do |original, *args|
        seen << Escalated::TicketAccess.current_actor
        original.call(*args)
      end
    end

    after { Escalated::ApplicationController.define_method(:current_user) { nil } }

    it 'never acts as the signed-in user for an allowed site' do
      post_json('/support/widget/tickets', ticket_params, origin: shop)

      expect(response).to have_http_status(:created)
      expect(seen).to eq([nil])
    end

    it 'keeps the signed-in user for same-origin requests' do
      post_json('/support/widget/tickets', ticket_params)

      expect(response).to have_http_status(:created)
      expect(seen).to eq([agent])
    end
  end

  describe 'host parameters' do
    it 'tells the widget it accepts them' do
      get '/support/widget/config'

      expect(response.parsed_body['accepts_metadata']).to be(true)
      expect(response.parsed_body.keys).to include('enabled', 'color', 'position', 'greeting', 'kb_enabled')
    end

    it 'stores sanitised host parameters on a widget ticket' do
      metadata = {
        order_number: 'A-1001', plan: 'pro', items: 3,
        page_url: 'https://shop.example.com/orders/A-1001',
        embedded_on: 'https://spoofed.example', source: 'spoofed',
        nested: { not: 'kept' }, 'bad key!' => 'dropped', note: 'a' * 600
      }
      post_json('/support/widget/tickets', ticket_params.merge(metadata: metadata), origin: shop)

      expect(response).to have_http_status(:created)
      metadata = created_ticket.metadata
      expect(metadata).to include(
        'source' => 'widget', 'order_number' => 'A-1001', 'plan' => 'pro', 'items' => 3,
        'page_url' => 'https://shop.example.com/orders/A-1001', 'embedded_on' => shop
      )
      expect(metadata).not_to have_key('nested')
      expect(metadata).not_to have_key('bad key!')
      expect(metadata['note'].length).to eq(500)
    end

    it 'drops a page_url that is not a web address' do
      post_json('/support/widget/tickets',
                ticket_params.merge(metadata: { page_url: 'javascript:alert(1)', plan: 'pro' }), origin: shop)

      expect(created_ticket.metadata).to eq('source' => 'widget', 'plan' => 'pro', 'embedded_on' => shop)
    end

    it 'does not record embedded_on for a same-origin ticket' do
      post_json('/support/widget/tickets', ticket_params.merge(metadata: { embedded_on: 'https://spoofed.example' }))

      expect(created_ticket.metadata).to eq('source' => 'widget')
    end

    it 'leaves widget tickets without host parameters unchanged' do
      post_json('/support/widget/tickets', ticket_params)

      expect(created_ticket.metadata).to eq('source' => 'widget')
    end

    it 'rejects metadata that is not an object or has more than 50 keys' do
      post_json('/support/widget/tickets', ticket_params.merge(metadata: 'order=1'), origin: shop)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.headers['Access-Control-Allow-Origin']).to eq(shop)

      post_json('/support/widget/tickets', ticket_params.merge(metadata: (1..51).index_by { |i| "k#{i}" }))
      expect(response).to have_http_status(:unprocessable_content)
      expect(Escalated::Ticket.count).to eq(0)
    end

    it 'lets an allowed site start a live chat and keeps its host parameters' do
      post_json('/support/widget/chat/start', {
                  name: 'John Doe', email: 'john@example.com', message: 'Hello',
                  metadata: { page_url: 'https://shop.example.com/cart', cart_total: 129.5, deep: { x: 1 },
                              ip: '10.0.0.1' }
                }, origin: shop)

      expect(response).to have_http_status(:created)
      expect(response.headers['Access-Control-Allow-Origin']).to eq(shop)
      session = Escalated::ChatSession.find(response.parsed_body['session_id'])
      expect(session.metadata).to eq(
        'page_url' => 'https://shop.example.com/cart', 'cart_total' => 129.5, 'ip' => '10.0.0.1',
        'embedded_on' => shop
      )
      expect(session.ticket.metadata).to include(
        'source' => 'chat', 'page_url' => 'https://shop.example.com/cart', 'embedded_on' => shop,
        'ip' => '127.0.0.1'
      )
      expect(session.ticket.metadata).not_to have_key('deep')
    end
  end

  describe 'embed.js' do
    let(:bundle) { Escalated::Engine.root.join('vendor/widget/escalated-widget.js') }

    it 'serves the standalone widget bundle for other sites to load' do
      get '/support/widget/embed.js'

      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Type']).to eq('application/javascript; charset=utf-8')
      expect(response.headers['Cache-Control']).to include('public').and include('max-age=3600')
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
      expect(response.headers['Cross-Origin-Resource-Policy']).to eq('cross-origin')
      expect(response.headers['Access-Control-Allow-Origin']).to eq('*')
      expect(response.body).to eq(File.read(bundle))
    end

    it 'answers 304 when the ETag still matches' do
      get '/support/widget/embed.js'
      etag = response.headers['ETag']
      expect(etag).to be_present

      get '/support/widget/embed.js', headers: { 'If-None-Match' => etag }

      expect(response).to have_http_status(:not_modified)
      expect(response.body).to be_empty
    end

    it 'is loadable by a cross-site script tag with forgery protection on' do
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true

      get '/support/widget/embed.js', headers: { 'Origin' => 'https://anywhere.example' }

      expect(response).to have_http_status(:ok)
    ensure
      ActionController::Base.allow_forgery_protection = original
    end

    it 'is part of the packaged gem' do
      spec = Gem::Specification.load(Escalated::Engine.root.join('escalated.gemspec').to_s)

      expect(spec.files).to include('vendor/widget/escalated-widget.js')
    end
  end

  describe 'admin settings' do
    let(:admin) { create(:user, :admin) }

    before do
      allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(admin) # rubocop:disable RSpec/AnyInstance
    end

    it 'saves the embedding sites and the widget switch, and shows them back' do
      Escalated::EscalatedSetting.set('widget_enabled', '0')

      post '/support/admin/settings', params: {
        widget_enabled: 'true', widget_color: '#112233',
        widget_allowed_origins: "https://shop.example.com\nhttps://*.brand.test"
      }

      expect(response).to be_redirect
      expect(Escalated::EscalatedSetting.get_bool('widget_enabled')).to be(true)
      expect(Escalated::EscalatedSetting.get('widget_color')).to eq('#112233')
      expect(Escalated::EscalatedSetting.get('widget_allowed_origins'))
        .to eq("https://shop.example.com\nhttps://*.brand.test")
      expect(Escalated::EscalatedSetting.all_as_hash['widget_allowed_origins'])
        .to eq("https://shop.example.com\nhttps://*.brand.test")
    end

    it 'refuses entries that are not bare origins and keeps the saved list' do
      Escalated::EscalatedSetting.set('widget_allowed_origins', 'https://shop.example.com')

      post '/support/admin/settings', params: {
        widget_allowed_origins: "https://shop.example.com/checkout\n*",
        ticket_reference_prefix: 'NEW'
      }

      expect(response).to be_redirect
      expect(session[:inertia_errors]).to include(widget_allowed_origins: a_string_including('*'))
      expect(Escalated::EscalatedSetting.get('widget_allowed_origins')).to eq('https://shop.example.com')
      expect(Escalated::EscalatedSetting.get('ticket_reference_prefix')).not_to eq('NEW')
    end

    it 'leaves the embedding sites alone when the form does not send them' do
      Escalated::EscalatedSetting.set('widget_allowed_origins', 'https://shop.example.com')

      post '/support/admin/settings', params: { ticket_reference_prefix: 'ESC' }

      expect(Escalated::EscalatedSetting.get('widget_allowed_origins')).to eq('https://shop.example.com')
    end
  end
end
