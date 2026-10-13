# frozen_string_literal: true

require 'rails_helper'
require 'cgi'

RSpec.describe 'Configurable ticket access' do
  let(:agent) { create(:user, :agent) }
  let(:department) { create(:escalated_department) }
  let!(:visible) { create(:escalated_ticket, department: department) }
  let!(:hidden) { create(:escalated_ticket, department: create(:escalated_department), assignee: agent) }

  before do
    department.agents << agent
    allow(Escalated.configuration).to receive(:visibility).and_return('department')
  end

  %i[show? update? reply? note? assign? close?].each do |action|
    it "checks department membership for #{action}" do
      expect(Escalated::TicketPolicy.new(agent, visible).public_send(action)).to be true
      expect(Escalated::TicketPolicy.new(agent, hidden).public_send(action)).to be false
    end
  end

  it 'scopes ticket queries and clears the actor after the block' do
    Escalated::TicketAccess.with_actor(agent) do
      expect(Escalated::Ticket.pluck(:id)).to eq([visible.id])
    end
    expect(Escalated::Ticket.count).to eq(2)
  end

  it 'keeps admin access within the existing database scope' do
    Escalated::TicketAccess.with_actor(create(:user, :admin)) do
      expect(Escalated::Ticket.count).to eq(2)
    end
  end

  it 'keeps legacy access when visibility is all' do
    allow(Escalated.configuration).to receive(:visibility).and_return('all')
    Escalated::TicketAccess.with_actor(agent) do
      expect(Escalated::Ticket.count).to eq(2)
    end
  end

  def sign_in_as(user)
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)
  end

  def page_props
    JSON.parse(CGI.unescapeHTML(response.body[%r{data-page="(.+?)"></div>}m, 1]))['props']
  end

  it 'scopes HTTP list, search, and direct detail access' do
    sign_in_as(agent)
    get '/support/agent/tickets'
    expect(page_props['tickets'].pluck('id')).to eq([visible.id])
    get '/support/agent/tickets', params: { search: hidden.reference }
    expect(page_props['tickets']).to be_empty
    get "/support/agent/tickets/#{hidden.id}"
    expect(response).to have_http_status(:not_found)
  end

  it 'scopes real bearer token lists and mutations' do
    token = Escalated::ApiToken.create_token(agent, 'access spec')
    headers = { 'Authorization' => "Bearer #{token[:plain_text_token]}" }
    get '/support/api/v1/tickets', headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['data'].pluck('id')).to eq([visible.id])
    patch "/support/api/v1/tickets/#{hidden.reference}/status", params: { status: 'closed' }, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'scopes bulk changes before selecting tickets' do
    sign_in_as(agent)
    post '/support/agent/tickets/bulk', params: { ticket_ids: [visible.id, hidden.id], action: 'close' }, as: :json
    expect(response).to have_http_status(:redirect)
    expect(hidden.reload.status).to eq('open')
    expect(visible.reload.status).to eq('closed')
  end

  it 'scopes widget lookups for authenticated agents' do
    Escalated::EscalatedSetting.set('widget_enabled', true)
    hidden.update!(guest_token: 'private-guest-token')
    sign_in_as(agent)
    get '/support/widget/tickets/private-guest-token'
    expect(response).to have_http_status(:not_found)
  end

  it 'scopes report aggregates and ticket links' do
    Escalated::TicketLink.create!(parent_ticket: visible, child_ticket: hidden, link_type: 'related')
    Escalated::TicketAccess.with_actor(agent) do
      expect(Escalated::Services::ReportingService.new.tickets_by_status.sum { |row| row[:count] }).to eq(1)
      expect(Escalated::TicketLink.count).to eq(0)
    end
  end

  it 'intersects account and department, distinguishing type and identifier case' do
    company = FakeProject.create!(id: 'North', name: 'North')
    allow(Escalated.configuration).to receive(:accounts).and_return(
      enabled: true, scope_agents: true, resolver: ->(_model) { company }
    )
    visible.update!(account_type: 'FakeProject', account_id: 'North')
    hidden.update!(account_type: 'FakeProject', account_id: 'North')
    create(:escalated_ticket, department: department, account_type: 'Other', account_id: 'North')
    create(:escalated_ticket, department: department, account_type: 'FakeProject', account_id: 'north')
    Escalated::TicketAccess.with_actor(agent) { expect(Escalated::Ticket.pluck(:id)).to eq([visible.id]) }
  end

  it 'fills account from subjects without overwriting a stored account through a stale instance' do
    first = FakeProject.create!(id: 'first', name: 'First')
    second = FakeProject.create!(id: 'second', name: 'Second')
    allow(Escalated.configuration).to receive(:accounts).and_return(
      enabled: true, resolver: ->(model) { model if model.is_a?(FakeProject) }
    )
    stale = Escalated::Ticket.find(visible.id)
    visible.attach_subject(first)
    stale.attach_subject(second)
    expect(visible.reload.account_id).to eq('first')
    expect(stale.account).to eq(first)
  end

  %i[account_type account_id].each do |field|
    it "preserves trailing spaces in #{field} for scopes and filters" do
      company = FakeProject.create!(id: '001', name: 'Company')
      allow(Escalated.configuration).to receive(:accounts).and_return(
        enabled: true, scope_agents: true, resolver: ->(_model) { company }
      )
      identity = { account_type: 'FakeProject', account_id: '001' }
      visible.update!(identity)
      create(:escalated_ticket, department: department, **identity.merge(field => "#{identity[field]} "))
      expect(Escalated::TicketAccess.filter_accounts(Escalated::Ticket.all, identity).pluck(:id)).to eq([visible.id])
      Escalated::TicketAccess.with_actor(agent) { expect(Escalated::Ticket.pluck(:id)).to eq([visible.id]) }
    end
  end

  it 'selects the most specific SLA and preserves it when the department changes' do
    allow(Escalated.configuration).to receive(:sla).and_return(enabled: true, targeted: true,
                                                               business_hours_only: false)
    create(:escalated_sla_policy, is_default: true)
    create(:escalated_sla_policy, ticket_type: 'incident')
    create(:escalated_sla_policy, department: department)
    both = create(:escalated_sla_policy, department: department, ticket_type: 'incident')
    ticket = Escalated::Drivers::LocalDriver.new.create_ticket(
      requester: agent, subject: 'Incident', description: 'Details',
      ticket_type: 'incident', department_id: department.id
    )
    expect(ticket.sla_policy_id).to eq(both.id)
    due = ticket.sla_first_response_due_at
    ticket.update!(department: hidden.department)
    expect(ticket.reload.sla_policy_id).to eq(both.id)
    expect(ticket.sla_first_response_due_at).to eq(due)
  end

  it 'matches complete account identities in all rule engines' do
    visible.update!(ticket_type: 'incident', account_type: 'Company', account_id: 'north')
    hidden.update!(ticket_type: 'incident', account_type: 'Partner', account_id: 'north')
    conditions = [{ 'field' => 'account', 'value' => { 'type' => 'Company', 'id' => 'north' } },
                  { 'field' => 'ticket_type', 'value' => 'incident' }]
    automation = Escalated::Automation.new(conditions: conditions)
    expect(Escalated::Services::AutomationRunner.new.send(:find_matching_tickets, automation).ids).to eq([visible.id])
    engine = Escalated::WorkflowEngine.new
    expect(engine.evaluate_conditions(conditions, visible)).to be true
    expect(engine.evaluate_conditions(conditions, hidden)).to be false
    rule = Escalated::EscalationRule.new(is_active: true, conditions: {
                                           'account' => { 'type' => 'Company',
                                                          'id' => 'north' }, 'ticket_type' => 'incident'
                                         })
    expect(rule.matches?(visible)).to be true
    expect(rule.matches?(hidden)).to be false
  end

  it 'does not email an assigned agent who cannot view the ticket' do
    expect(Escalated::TicketMailer.ticket_assigned(hidden).message.to).to be_nil
  end

  it 'hides tickets when an agent has no department and never exposes unassigned tickets' do
    create(:escalated_ticket, department: nil)
    department.agents.delete(agent)
    Escalated::TicketAccess.with_actor(agent) { expect(Escalated::Ticket.count).to eq(0) }
  end

  it 'grants no account tickets when the resolver returns nil' do
    allow(Escalated.configuration).to receive(:accounts).and_return(
      enabled: true, scope_agents: true, resolver: ->(_model) {}
    )
    Escalated::TicketAccess.with_actor(agent) { expect(Escalated::Ticket.count).to eq(0) }
  end

  it 'rejects partial account filters before querying' do
    allow(Escalated.configuration).to receive(:accounts).and_return(enabled: true)
    sign_in_as(agent)
    get '/support/agent/tickets', params: { account_id: 'one' }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'checks chat access and private guest session tokens' do
    session = Escalated::ChatSession.create!(ticket: hidden, customer_session_id: 'private-session', status: 'waiting')
    expect(Escalated::TicketAccess.chat_allowed?(agent, hidden)).to be false
    expect(Escalated::TicketAccess.chat_allowed?(nil, hidden)).to be false
    expect(Escalated::TicketAccess.chat_allowed?(nil, hidden, session.customer_session_id)).to be true
    expect do
      Escalated::Services::ChatSessionService.assign_agent(session, agent.id)
    end.to raise_error(ArgumentError, 'Agent cannot access this ticket')
    expect(session.reload.agent_id).to be_nil
  end

  it 'rejects incomplete account rule conditions' do
    condition = { 'field' => 'account', 'operator' => 'not_equals', 'value' => { 'id' => 'north' } }
    expect(Escalated::WorkflowEngine.new.evaluate_conditions([condition], visible)).to be false
    rule = Escalated::EscalationRule.new(is_active: true, conditions: { 'account' => { 'id' => 'north' } })
    expect(rule.matches?(visible)).to be false
  end
end
