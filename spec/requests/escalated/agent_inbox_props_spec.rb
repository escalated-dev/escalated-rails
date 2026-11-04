# frozen_string_literal: true

require 'cgi'
require 'json'
require 'rails_helper'

# The agent panel's optional `inbox` and `queue` props, and the list filters
# its rail, views and stat strip link to (shared frontend docs/agent-panel.md),
# as escalated-laravel sends them.
#
# Every number here must be what the agent would get by opening the list it
# labels, so the specs check counts against the list and against visibility.
RSpec.describe 'Agent inbox props', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:agent) { create(:user, :agent, email: 'inbox-agent@example.test') }
  let(:other) { create(:user, :agent, email: 'inbox-other@example.test') }
  let(:signed_in) { { user: agent } }

  def built_in_view_ids
    %w[urgent sla_at_risk waiting_on_me waiting_on_customer recently_updated]
  end

  around do |example|
    previous = Escalated.configuration.agent_inbox_cache_seconds
    Escalated.configuration.agent_inbox_cache_seconds = 0
    example.run
  ensure
    Escalated.configuration.agent_inbox_cache_seconds = previous
  end

  before do
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user) { signed_in[:user] }
  end

  def page_for(path, params = {})
    get path, params: params
    expect(response).to have_http_status(:ok)
    encoded = response.body[%r{data-page="(.+?)"></div>}m, 1]
    raise "no Inertia page payload in the response for #{path}" unless encoded

    JSON.parse(CGI.unescapeHTML(encoded))
  end

  def props_for(path, params = {})
    page_for(path, params)['props']
  end

  def inbox_ticket(attributes = {})
    create(:escalated_ticket, { priority: :low, status: :open }.merge(attributes))
  end

  it 'sends inbox counts, built-in views, stats and the queue on the ticket list' do
    inbox_ticket(assigned_to: agent.id, priority: :urgent)
    inbox_ticket(assigned_to: agent.id, status: :waiting_on_customer)
    inbox_ticket(assigned_to: agent.id, status: :resolved, resolved_at: Time.current)
    inbox_ticket(assigned_to: agent.id, status: :resolved, resolved_at: 2.days.ago)
    inbox_ticket(assigned_to: agent.id, snoozed_until: 1.day.from_now)
    inbox_ticket
    inbox_ticket(status: :closed)
    inbox_ticket(assigned_to: other.id)

    page = page_for('/support/agent/tickets')
    expect(page['component']).to eq('Escalated/Agent/TicketIndex')

    inbox = page['props']['inbox']
    expect(inbox.keys).to eq(%w[counts views stats])
    # Unresolved, unsnoozed tickets in each queue.
    expect(inbox['counts']).to eq('mine' => 2, 'unassigned' => 1, 'all' => 4)
    expect(inbox['views'].pluck('id')).to eq(built_in_view_ids)
    expect(inbox['views'][0].keys).to eq(%w[id name count filters])
    expect(inbox['views'][0]).to eq('id' => 'urgent', 'name' => 'Urgent', 'count' => 1,
                                    'filters' => { 'priority' => 'urgent', 'open' => 1 })
    expect(inbox['stats'].keys).to eq(%w[open urgent sla_at_risk resolved_today])
    # The "all" queue: three tickets with status open, one urgent, one resolved today.
    expect(inbox['stats']).to eq('open' => 3, 'urgent' => 1, 'sla_at_risk' => 0, 'resolved_today' => 1)
    expect(page['props']['queue']).to eq('key' => 'all', 'title' => 'All tickets')
  end

  it 'sends each built-in view with the filters its list opens with' do
    inbox_ticket(assigned_to: agent.id, priority: :urgent)
    inbox_ticket(assigned_to: agent.id, status: :waiting_on_customer)
    inbox_ticket
    inbox_ticket(status: :closed)

    views = props_for('/support/agent/tickets')['inbox']['views'].index_by { |view| view['id'] }
    expect(views['waiting_on_customer']['count']).to eq(1)
    expect(views['waiting_on_customer']['filters']).to eq('assigned_to' => agent.id, 'status' => 'waiting_on_customer')
    expect(views['waiting_on_me']['filters']).to eq('assigned_to' => agent.id, 'status' => 'waiting_on_agent')
    expect(views['sla_at_risk']['filters']).to eq('sla_at_risk' => 1)
    expect(views['recently_updated']['filters']).to eq('open' => 1, 'updated_within_hours' => 24,
                                                       'sort_by' => 'updated_at')
    expect(views['recently_updated']['count']).to eq(3)
  end

  {
    'mine' => ['assigned_to={me}', 'mine', 'My inbox', [1, 1, 0, 1]],
    'mine, by alias' => ['assigned=me', 'mine', 'My inbox', [1, 1, 0, 1]],
    'mine with a stat tile on' => ['assigned_to={me}&priority=urgent', 'mine', 'My inbox', [1, 1, 0, 1]],
    'unassigned' => ['unassigned=1', 'unassigned', 'Unassigned', [2, 1, 0, 1]],
    'all' => ['', 'all', 'All tickets', [3, 2, 0, 2]],
    'a built-in view by its filters' => ['priority=urgent&open=1', 'view:urgent', 'Urgent', [2, 2, 0, 0]],
    'a built-in view by id' => ['view=urgent', 'view:urgent', 'Urgent', [2, 2, 0, 0]]
  }.each do |label, (query, key, title, stats)|
    it "names and scopes the queue from the list query: #{label}" do
      inbox_ticket(assigned_to: agent.id, priority: :urgent)
      inbox_ticket(assigned_to: agent.id, status: :resolved, resolved_at: Time.current)
      inbox_ticket
      inbox_ticket(status: :resolved, resolved_at: Time.current)
      inbox_ticket(priority: :urgent)

      props = props_for("/support/agent/tickets?#{query.sub('{me}', agent.id.to_s)}")

      expect(props['queue']).to eq('key' => key, 'title' => title)
      expect(props['inbox']['stats']).to eq(%w[open urgent sla_at_risk resolved_today].zip(stats).to_h)
    end
  end

  it "lists the agent's own and shared saved views with counts, but not other agents' private views" do
    mine = Escalated::SavedView.create!(user_id: agent.id, name: 'High priority', filters: { priority: 'high' },
                                        position: 1)
    shared = Escalated::SavedView.create!(user_id: other.id, name: 'Waiting', filters: { status: 'waiting_on_agent' },
                                          is_shared: true, position: 2)
    Escalated::SavedView.create!(user_id: other.id, name: 'Private', filters: { priority: 'low' }, position: 0)

    inbox_ticket(priority: :high)
    inbox_ticket(priority: :high)
    inbox_ticket(priority: :high, status: :closed)
    inbox_ticket(status: :waiting_on_agent)

    views = props_for('/support/agent/tickets')['inbox']['views']
    saved = views.reject { |view| built_in_view_ids.include?(view['id']) }

    expect(saved).to eq([
                          { 'id' => mine.id, 'name' => 'High priority', 'count' => 2,
                            'filters' => { 'priority' => 'high' } },
                          { 'id' => shared.id, 'name' => 'Waiting', 'count' => 1,
                            'filters' => { 'status' => 'waiting_on_agent' } }
                        ])
  end

  %w[id filters].each do |by|
    it "selects a saved view as the queue, by #{by}, and filters the list with it" do
      view = Escalated::SavedView.create!(user_id: agent.id, name: 'High priority', filters: { priority: 'high' },
                                          position: 1)
      high = inbox_ticket(priority: :high)
      inbox_ticket(priority: :low)

      query = by == 'id' ? "view=#{view.id}" : 'priority=high'
      props = props_for("/support/agent/tickets?#{query}")

      expect(props['queue']).to eq('key' => "view:#{view.id}", 'title' => 'High priority')
      expect(props['tickets']['data'].pluck('id')).to eq([high.id])
    end
  end

  it "does not let an agent select another agent's private view" do
    hidden = Escalated::SavedView.create!(user_id: other.id, name: 'Private', filters: { priority: 'high' },
                                          position: 1)
    inbox_ticket(priority: :high)
    inbox_ticket(priority: :low)

    props = props_for("/support/agent/tickets?view=#{hidden.id}")

    expect(props['queue']).to eq('key' => 'all', 'title' => 'All tickets')
    expect(props['tickets']['total']).to eq(2)
  end

  it 'gives every built-in view the count its own list shows' do
    inbox_ticket(assigned_to: agent.id, priority: :urgent)
    inbox_ticket(priority: :urgent, status: :closed)
    inbox_ticket(assigned_to: agent.id, status: :waiting_on_agent)
    inbox_ticket(assigned_to: agent.id, status: :waiting_on_customer)
    inbox_ticket(sla_breached: true)
    inbox_ticket(sla_resolution_due_at: 30.minutes.from_now)
    inbox_ticket.update_columns(updated_at: 3.days.ago)

    views = props_for('/support/agent/tickets')['inbox']['views']

    views.each do |view|
      total = props_for('/support/agent/tickets', view['filters'])['tickets']['total']
      expect(view['count']).to eq(total), "view #{view['id']} counts #{view['count']} but its list shows #{total}"
    end

    expect(views.to_h { |view| [view['id'], view['count']] }).to eq(
      'urgent' => 1, 'sla_at_risk' => 2, 'waiting_on_me' => 1, 'waiting_on_customer' => 1, 'recently_updated' => 5
    )
  end

  it 'counts only tickets the agent may see' do
    allow(Escalated.configuration).to receive(:visibility).and_return('department')
    support = create(:escalated_department)
    billing = create(:escalated_department)
    support.agents << agent

    inbox_ticket(department: support, assigned_to: agent.id, priority: :urgent)
    inbox_ticket(department: support)
    inbox_ticket(department: billing)
    inbox_ticket(department: billing, priority: :urgent)
    inbox_ticket(department: billing, status: :resolved, resolved_at: Time.current)

    inbox = props_for('/support/agent/tickets')['inbox']

    expect(inbox['counts']).to eq('mine' => 1, 'unassigned' => 1, 'all' => 2)
    expect(inbox['stats']).to eq('open' => 2, 'urgent' => 1, 'sla_at_risk' => 0, 'resolved_today' => 0)
    expect(inbox['views'].find { |view| view['id'] == 'urgent' }['count']).to eq(1)
  end

  it 'filters the list to tickets whose SLA is breached or due within the hour' do
    breached = inbox_ticket(sla_breached: true)
    response_due = inbox_ticket(sla_first_response_due_at: 20.minutes.from_now)
    resolution_due = inbox_ticket(sla_resolution_due_at: 50.minutes.from_now)
    inbox_ticket(sla_first_response_due_at: 20.minutes.from_now, first_response_at: 1.minute.ago)
    inbox_ticket(sla_resolution_due_at: 3.hours.from_now)
    inbox_ticket(sla_breached: true, status: :resolved, resolved_at: Time.current)
    inbox_ticket

    props = props_for('/support/agent/tickets', sla_at_risk: 1)

    expect(props['tickets']['data'].pluck('id')).to contain_exactly(breached.id, response_due.id, resolution_due.id)
    expect(props['inbox']['stats']['sla_at_risk']).to eq(3)
  end

  it 'filters the list to tickets resolved today' do
    today = inbox_ticket(status: :resolved, resolved_at: Time.current.beginning_of_day + 1.minute)
    inbox_ticket(status: :resolved, resolved_at: 1.day.ago.beginning_of_day)
    inbox_ticket

    props = props_for('/support/agent/tickets', status: 'resolved', resolved_today: 1)

    expect(props['tickets']['data'].pluck('id')).to eq([today.id])
  end

  it 'filters the list to tickets updated within the given hours' do
    fresh = inbox_ticket
    inbox_ticket.update_columns(updated_at: 2.days.ago)

    props = props_for('/support/agent/tickets', updated_within_hours: 24)

    expect(props['tickets']['data'].pluck('id')).to eq([fresh.id])
  end

  it 'filters the list to unresolved tickets with open=1' do
    open = inbox_ticket
    inbox_ticket(status: :resolved, resolved_at: Time.current)
    inbox_ticket(status: :closed)

    expect(props_for('/support/agent/tickets', open: 1)['tickets']['data'].pluck('id')).to eq([open.id])
  end

  it 'filters the list to the agent with assigned=me' do
    mine = inbox_ticket(assigned_to: agent.id)
    inbox_ticket(assigned_to: other.id)
    inbox_ticket

    expect(props_for('/support/agent/tickets', assigned: 'me')['tickets']['data'].pluck('id')).to eq([mine.id])
  end

  [
    { 'sla_at_risk' => 'soon' },
    { 'resolved_today' => 'maybe' },
    { 'open' => 'perhaps' },
    { 'updated_within_hours' => '0' },
    { 'updated_within_hours' => 'a day' },
    { 'updated_within_hours' => '9000' }
  ].each do |query|
    it "sends malformed values for the new filters on a page visit back with errors: #{query}" do
      # escalated-laravel's $request->validate(): a redirect back with the errors
      # in the session (the next page's `errors` prop), never a raw 422, which
      # the Inertia client shows as an error modal.
      headers = { 'X-Inertia' => 'true', 'Referer' => '/support/agent/tickets?assigned=me' }
      get '/support/agent/tickets', params: query, headers: headers

      expect(response).to redirect_to('/support/agent/tickets?assigned=me')
      expect(session[:inertia_errors]&.keys).to eq(query.keys)
      expect(session[:inertia_errors].values).to all(be_a(String))
    end

    it "answers a JSON client's malformed filter with a 422: #{query}" do
      get '/support/agent/tickets', params: query, headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['errors'].keys).to eq(query.keys)
      expect(response.parsed_body['message']).to be_present
    end
  end

  it 'sends a browser visit with a malformed filter and no referer back to the list' do
    get '/support/agent/tickets', params: { sla_at_risk: 'soon' }

    expect(response).to redirect_to('/support/agent/tickets')
    expect(session[:inertia_errors]&.keys).to eq(['sla_at_risk'])
  end

  it 'previews the latest customer-visible message, never an internal note' do
    ticket = inbox_ticket
    create(:escalated_reply, ticket: ticket, author: agent, body: 'Customer-visible answer', is_internal: false,
                             created_at: 5.minutes.ago)
    create(:escalated_reply, ticket: ticket, author: agent, body: 'Secret internal note', is_internal: true,
                             created_at: Time.current)

    row = props_for('/support/agent/tickets')['tickets']['data'].first

    expect(row['latest_reply']['body']).to eq('Customer-visible answer')
    expect(Time.zone.parse(row['last_reply_at'])).to be_within(3.seconds).of(5.minutes.ago)
    # Escalated tracks no per-agent read state or customer presence, so it sends neither.
    expect(row).not_to have_key('is_unread')
    expect(row).not_to have_key('requester_online')
  end

  it 'sends inbox and the queue the agent last opened on the ticket page' do
    ticket = inbox_ticket(assigned_to: agent.id)
    inbox_ticket

    page = page_for("/support/agent/tickets/#{ticket.reference}")
    expect(page['component']).to eq('Escalated/Agent/TicketShow')
    expect(page['props']['queue']).to eq('key' => 'all', 'title' => 'All tickets')
    expect(page['props']['inbox']['counts']).to eq('mine' => 1, 'unassigned' => 1, 'all' => 2)
    expect(page['props']['inbox'].keys).to eq(%w[counts views stats])

    props_for('/support/agent/tickets', assigned_to: agent.id)

    props = props_for("/support/agent/tickets/#{ticket.reference}")
    expect(props['queue']).to eq('key' => 'mine', 'title' => 'My inbox')
    expect(props['inbox']['stats']).to eq('open' => 1, 'urgent' => 0, 'sla_at_risk' => 0, 'resolved_today' => 0)
  end

  it 'caches the inbox per agent for the configured seconds' do
    Escalated.configuration.agent_inbox_cache_seconds = 30
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

    inbox_ticket(assigned_to: agent.id)
    expect(props_for('/support/agent/tickets')['inbox']['counts']['mine']).to eq(1)

    inbox_ticket(assigned_to: agent.id)
    inbox_ticket(assigned_to: other.id)

    expect(props_for('/support/agent/tickets')['inbox']['counts']['mine']).to eq(1)
    signed_in[:user] = other
    expect(props_for('/support/agent/tickets')['inbox']['counts']['mine']).to eq(1)
    signed_in[:user] = agent

    travel 31.seconds do
      expect(props_for('/support/agent/tickets')['inbox']['counts']['mine']).to eq(2)
    end
  end

  it 'sends no inbox in cloud mode, where tickets are not stored locally' do
    ticket = inbox_ticket
    allow(Escalated.configuration).to receive(:cloud?).and_return(true)

    props = props_for("/support/agent/tickets/#{ticket.reference}")

    expect(props).not_to have_key('inbox')
    expect(props['queue']).to eq('key' => 'all', 'title' => 'All tickets')
  end

  %w[Escalated/Agent/TicketIndex Escalated/Agent/TicketShow].each do |component|
    it "sends #{component} every prop it declares" do
      ticket = inbox_ticket
      path = component.end_with?('Index') ? '/support/agent/tickets' : "/support/agent/tickets/#{ticket.reference}"

      page = page_for(path)

      expect(page['component']).to eq(component)
      declared = declared_props(component)
      expect(declared - page['props'].keys).to eq([])
      expect(declared).to include('inbox', 'queue')
    end
  end
end
