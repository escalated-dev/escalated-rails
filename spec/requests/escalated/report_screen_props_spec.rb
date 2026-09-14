# frozen_string_literal: true

require 'cgi'
require 'json'
require 'rails_helper'

# The report screens are handed the props they actually read.
#
# A page name that resolves is not a screen that works. Inertia passes props by
# name, and a name the component does not declare is not passed at all -- it
# lands on the root element as an attribute. The screen renders its defaults,
# which for a report is zeroes and empty charts, on a 200, and that is
# indistinguishable from a quiet period.
#
# Every action in AdvancedReportsController used to send `{ data:, filters: }`,
# which no report component reads. All nine screens were empty, and six of them
# rendered page names the frontend does not ship at all.
#
# The manifest at spec/fixtures/escalated-pages.json publishes what each
# component declares. This asserts the response against it, in both directions.
module ReportScreenProps
  MANIFEST_PATH = File.expand_path('../../fixtures/escalated-pages.json', __dir__)

  # Inertia shares these with every page; they are not a screen's own business
  # and no component declares them.
  SHARED_PROPS = %w[errors auth current_user flash escalated plugin_ui].freeze

  SCREENS = {
    'sla_trends' => 'Escalated/Admin/Reports/SlaTrends',
    'response_times' => 'Escalated/Admin/Reports/ResponseTimes',
    'resolution_times' => 'Escalated/Admin/Reports/ResolutionTimes',
    'agent_ranking' => 'Escalated/Admin/Reports/AgentRanking',
    'cohorts' => 'Escalated/Admin/Reports/Cohorts',
    'comparison' => 'Escalated/Admin/Reports/Comparison'
  }.freeze
end

RSpec.describe 'Report screen props', type: :request do
  let(:admin) { create(:user, :admin, email: 'admin-report-props@example.test') }

  before { sign_in_as(admin) }

  def sign_in_as(user)
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)
  end

  def manifest
    @manifest ||= JSON.parse(File.read(ReportScreenProps::MANIFEST_PATH))
  end

  # Inertia HTML responses carry the page JSON-encoded inside data-page="...",
  # HTML-escaped. Asking for the JSON form instead means matching the asset
  # version, and a mismatch answers 409 with an empty body -- which reads here
  # as a screen sending no props at all.
  def get_screen(action)
    get "/support/admin/reports/advanced/#{action}"

    encoded = response.body[%r{data-page="(.+?)"></div>}m, 1]
    raise "no Inertia page payload in the response for #{action}" unless encoded

    JSON.parse(CGI.unescapeHTML(encoded))
  end

  ReportScreenProps::SCREENS.each do |action, page|
    it "sends #{page} every prop it declares, and nothing it does not" do
      body = get_screen(action)

      expect(response).to have_http_status(:ok)
      expect(body['component']).to eq(page)

      expect(manifest['props']).to have_key(page)
      declared = manifest['props'][page]['props']
      sent = body['props'].keys - ReportScreenProps::SHARED_PROPS

      missing = declared - sent
      unread = sent - declared

      expect(missing).to eq([]),
                         "#{page} declares props this response never sends, so they render as their " \
                         "defaults:\n  #{missing.join("\n  ")}"

      expect(unread).to eq([]),
                        "#{page} is sent props it does not declare, so they are dropped on the root " \
                        "element:\n  #{unread.join("\n  ")}"
    end
  end

  it 'has a manifest that describes props at all' do
    # A fixture that lost its props would make every example above pass by
    # comparing two empty lists.
    expect(manifest).to have_key('props')
    expect(manifest['props'].length).to be > 50
    expect(manifest['props']['Escalated/Admin/Reports/AgentRanking']['props']).to eq(%w[agents period_days])
  end

  it 'still answers the five paths that are now two screens' do
    # They were in the routes long enough to be linked, so they redirect rather
    # than 404.
    %w[frt_distribution frt_trends frt_by_agent].each do |action|
      get "/support/admin/reports/advanced/#{action}"
      expect(response).to redirect_to('/support/admin/reports/advanced/response_times')
    end

    %w[resolution_distribution resolution_trends].each do |action|
      get "/support/admin/reports/advanced/#{action}"
      expect(response).to redirect_to('/support/admin/reports/advanced/resolution_times')
    end

    get '/support/admin/reports/advanced/cohort'
    expect(response).to redirect_to('/support/admin/reports/advanced/cohorts')
  end
end
