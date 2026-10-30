# frozen_string_literal: true

require 'rails_helper'

# The built-in route list (Escalated::RouteList) the shared frontend's
# route(name, params) calls resolve against.
#
# Every name the frontend calls must be either in the list or in NOT_SERVED
# below. A name in neither leaves a button that goes nowhere, which is what
# hosts had to hand-map in a window.route shim before this list existed.
module RouteListSpec
  NAMES_FIXTURE = File.expand_path('../../fixtures/frontend-route-names.txt', __dir__)

  # Names the frontend calls that this engine has no endpoint for.
  NOT_SERVED = [
    # Agents cannot snooze here; only the admin ticket screen has snooze and
    # unsnooze (SnoozeButton is shared by both screens).
    'escalated.agent.tickets.snooze',
    'escalated.agent.tickets.unsnooze',
    # Ticket links, merge and side conversations: the admin routes are drawn,
    # but their controllers are written against columns, associations and a
    # service method this engine's models do not have (every call is a 500),
    # and merge-search needs a ticket the merge dialog does not send.
    'escalated.admin.tickets.links.index',
    'escalated.admin.tickets.links.store',
    'escalated.admin.tickets.links.destroy',
    'escalated.admin.tickets.merge',
    'escalated.admin.tickets.merge-search',
    'escalated.admin.tickets.side-conversations.index',
    'escalated.admin.tickets.side-conversations.store',
    'escalated.admin.tickets.side-conversations.reply',
    'escalated.admin.tickets.side-conversations.close',
    # The all-workflows run log: only a per-workflow log route exists, and its
    # serializer reads a WorkflowLog column that is not there.
    'escalated.admin.workflows.logs',
    # The host owns sign-in, and the engine has no configurable login path.
    # A host maps it with config.route_overrides = { 'login' => '/users/sign_in' }.
    'login'
  ].freeze

  # Handlers that accept any path under them, so recognising a uri there proves
  # nothing about the route the name is meant for.
  CATCH_ALLS = %w[
    escalated/plugins/pages#show escalated/plugins/endpoints#handle escalated/plugins/webhooks#handle
    escalated/widget#preflight
  ].freeze
end

RSpec.describe Escalated::RouteList do
  let(:frontend_names) do
    File.readlines(RouteListSpec::NAMES_FIXTURE, chomp: true).map(&:strip).reject { |line| line.empty? || line.start_with?('#') }
  end

  it 'covers every route name the frontend calls' do
    missing = frontend_names - described_class.routes.keys - RouteListSpec::NOT_SERVED

    expect(missing).to eq([]), "frontend names neither listed nor allowlisted: #{missing.join(', ')}"
  end

  it 'keeps the not-served allowlist honest' do
    expect(RouteListSpec::NOT_SERVED & described_class.routes.keys).to eq([])
    expect(RouteListSpec::NOT_SERVED - frontend_names).to eq([])
  end

  it 'shares uris in the Ziggy shape, under the route prefix' do
    route = described_class.routes['escalated.admin.tickets.show']

    expect(route).to eq(uri: 'support/admin/tickets/{id}', methods: %w[GET HEAD])
    expect(described_class.routes.values.pluck(:uri)).to all(start_with('support/'))
  end

  it 'maps every listed name onto a route the engine really serves, with matching parameter names' do
    failures = described_class.routes.flat_map do |name, route|
      samples = {}
      path = "/#{route[:uri]}".gsub(/\{(\w+)\??\}/) { samples[Regexp.last_match(1)] = "s#{samples.size + 1}x" }

      (route[:methods] - %w[HEAD]).filter_map do |method|
        recognized = Rails.application.routes.recognize_path(path, method: method)
        target = "#{recognized[:controller]}##{recognized[:action]}"
        params_match = samples.all? { |key, value| recognized[key.to_sym].to_s == value }

        guest_catch_all = target == 'escalated/guest/tickets#show' && name != 'escalated.guest.tickets.show'

        if RouteListSpec::CATCH_ALLS.include?(target) || guest_catch_all
          "#{name}: #{method} #{path} only reaches the catch-all #{target}"
        elsif !params_match
          unmatched = recognized.except(:controller, :action)
          "#{name}: #{method} #{path} placeholders #{samples.keys} do not match #{unmatched}"
        end
      rescue ActionController::RoutingError
        "#{name}: #{method} #{path} is not routed"
      end
    end

    expect(failures).to eq([])
  end

  it 'follows the configured route prefix' do
    allow(Escalated.configuration).to receive(:route_prefix).and_return('/helpdesk/')

    expect(described_class.routes['escalated.customer.kb.index'][:uri]).to eq('helpdesk/customer/kb')
  end

  it 'lets the host override and add names' do
    allow(Escalated.configuration).to receive(:route_overrides).and_return(
      'login' => '/users/sign_in',
      'escalated.customer.kb.index' => { uri: 'help', methods: %w[GET HEAD] }
    )

    expect(described_class.routes['login']).to eq(uri: 'users/sign_in', methods: %w[GET HEAD])
    expect(described_class.routes['escalated.customer.kb.index']).to eq(uri: 'help', methods: %w[GET HEAD])
  end

  it 'ships a route() helper that defers to a host helper and to window.Ziggy' do
    helper = described_class::ROUTE_HELPER

    expect(helper).to include("if (typeof window.route === 'function') return;")
    expect(helper).to include('window.Ziggy && window.Ziggy.routes')
    expect(helper).to include("return '#';")
  end

  it 'gives host layouts a tag that installs the helper' do
    tag = ActionView::Base.empty.escalated_route_helper_tag

    expect(tag).to start_with('<script>').and include('window.route = function (name, params)')
  end
end
