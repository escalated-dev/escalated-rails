# frozen_string_literal: true

require 'cgi'
require 'json'

# Helpers for request specs that drive a screen the way the shared frontend
# does: read the Inertia page out of an HTML response, and send the JSON body
# plus X-Inertia header that an Inertia form visit sends.
module InertiaPageHelpers
  MANIFEST_PATH = File.expand_path('../fixtures/escalated-pages.json', __dir__)

  # Shared with every page by ApplicationController; no component declares them.
  SHARED_PROPS = %w[errors auth current_user flash escalated plugin_ui ziggy].freeze

  def inertia_page
    encoded = response.body[%r{data-page="(.+?)"></div>}m, 1]
    raise "no Inertia page payload in the response (status #{response.status})" unless encoded

    JSON.parse(CGI.unescapeHTML(encoded))
  end

  def inertia_visit(method, path, body = nil, referer: nil)
    headers = { 'X-Inertia' => 'true' }
    headers['Referer'] = "http://www.example.com#{referer}" if referer
    send(method, path, params: body, headers: headers, as: :json)
  end

  def page_manifest
    @page_manifest ||= JSON.parse(File.read(MANIFEST_PATH))
  end

  # The props a component declares (from the manifest the frontend publishes).
  def declared_props(component)
    page_manifest.fetch('props').fetch(component).fetch('props')
  end

  # Fetch +path+ and assert it renders +component+ with every prop the
  # component declares and none it does not. Returns the page.
  def expect_screen(path, component)
    get path
    expect(response).to have_http_status(:ok)

    page = inertia_page
    expect(page['component']).to eq(component)

    sent = page['props'].keys - SHARED_PROPS
    declared = declared_props(component)
    expect(declared - sent).to eq([]), "#{component} never receives: #{(declared - sent).join(', ')}"
    expect(sent - declared).to eq([]), "#{component} is sent props it does not declare: #{(sent - declared).join(', ')}"

    page
  end
end

RSpec.configure do |config|
  config.include InertiaPageHelpers, type: :request
end
