# frozen_string_literal: true

require 'rails_helper'

# The report screens behind the shared Reports/Dashboard tabs: the dashboard
# itself, Agent Metrics, SLA, CSAT, and the per-agent detail the ranking links
# to. Props follow escalated-laravel's ReportController (and, for AgentDetail,
# what the component declares, which Laravel does not send yet).
RSpec.describe 'Report pages', type: :request do
  let(:admin) { create(:user, :admin, name: 'Ada Admin', email: 'admin-report-pages@example.test') }
  let(:agent) { create(:user, :agent, name: 'Grace Agent', email: 'grace@example.test') }
  let(:policy) { create(:escalated_sla_policy, name: 'Standard') }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(admin)
  end

  # A ticket created +created+ ago, answered and resolved the given hours after.
  def ticket(created:, assignee: agent, response_hours: nil, resolution_hours: nil, **columns)
    record = create(:escalated_ticket, assigned_to: assignee&.id)
    created_at = created.ago
    record.update_columns(
      {
        created_at: created_at,
        first_response_at: response_hours && (created_at + response_hours.hours),
        resolved_at: resolution_hours && (created_at + resolution_hours.hours)
      }.merge(columns)
    )
    record
  end

  def rate(ticket, rating, at: 1.day.ago)
    Escalated::SatisfactionRating.create!(ticket: ticket, rating: rating, created_at: at)
  end

  describe 'the dashboard' do
    it 'sends the tabs their figures' do
      answered = ticket(created: 2.days, response_hours: 2, resolution_hours: 10, sla_policy_id: policy.id)
      ticket(created: 1.day, response_hours: 4, sla_policy_id: policy.id, sla_breached: true)
      ticket(created: 40.days, response_hours: 50)
      rate(answered, 4)

      page = expect_screen('/support/admin/reports/dashboard', 'Escalated/Admin/Reports/Dashboard')
      props = page['props']

      expect(props['period_days']).to eq(30)
      expect(props['volume'].sum { |d| d['value'] }).to eq(2)
      expect(props['volume']).to all(include('label', 'value'))
      expect(props['by_status']).to include('label' => 'open', 'value' => 3)
      expect(props['by_priority']).to include('label' => 'medium', 'value' => 3)
      expect(props['avg_response_hours']).to eq(3.0)
      expect(props['avg_resolution_hours']).to eq(10.0)
      expect(props['sla_compliance']).to eq(50.0)
      expect(props['csat_average']).to eq(4.0)
      expect(props['agent_performance'].sole).to include(
        'agent_id' => agent.id, 'agent_name' => 'Grace Agent', 'total_tickets' => 2, 'resolved_tickets' => 1,
        'avg_response_hours' => 3.0, 'avg_resolution_hours' => 10.0
      )
    end

    it 'takes the period in days' do
      ticket(created: 40.days)

      get '/support/admin/reports/dashboard', params: { days: 90 }

      expect(inertia_page.dig('props', 'period_days')).to eq(90)
      expect(inertia_page.dig('props', 'volume').sum { |d| d['value'] }).to eq(1)
    end
  end

  it 'renders agent metrics' do
    ticket(created: 2.days, response_hours: 1, resolution_hours: 5)

    page = expect_screen('/support/admin/reports/agents?days=7', 'Escalated/Admin/Reports/AgentMetrics')

    expect(page.dig('props', 'period_days')).to eq(7)
    expect(page.dig('props', 'agents').sole).to include(
      'agent_id' => agent.id, 'agent_name' => 'Grace Agent', 'total_tickets' => 1, 'resolved_tickets' => 1,
      'avg_response_hours' => 1.0, 'avg_resolution_hours' => 5.0
    )
  end

  it 'renders the SLA report' do
    create(:escalated_sla_policy, name: 'Unused')
    met = ticket(created: 3.days, response_hours: 1, sla_policy_id: policy.id,
                 sla_first_response_due_at: 3.days.ago + 4.hours)
    late = ticket(created: 2.days, response_hours: 6, sla_policy_id: policy.id, sla_breached: true,
                  sla_first_response_due_at: 2.days.ago + 4.hours, sla_resolution_due_at: 1.day.ago)

    page = expect_screen('/support/admin/reports/sla', 'Escalated/Admin/Reports/SlaReport')
    props = page['props']

    expect(props['compliance_rate']).to eq(50.0)
    expect(props['compliance_by_policy']).to contain_exactly(
      { 'policy_name' => 'Standard', 'total' => 2, 'met' => 1, 'breached' => 1 },
      { 'policy_name' => 'Unused', 'total' => 0, 'met' => 0, 'breached' => 0 }
    )
    expect(props['breaches'].sole).to include(
      'id' => late.id, 'reference' => late.reference, 'subject' => late.subject,
      'sla_first_response_breached' => true, 'sla_resolution_breached' => true,
      'sla_policy' => include('id' => policy.id, 'name' => 'Standard')
    )
    expect(props['breaches'].pluck('id')).not_to include(met.id)
  end

  it 'renders the CSAT report' do
    first = ticket(created: 3.days)
    second = ticket(created: 2.days)
    ticket(created: 1.day)
    ticket(created: 1.day, assignee: nil)
    rate(first, 5, at: 2.days.ago)
    rate(second, 3, at: 1.day.ago)

    page = expect_screen('/support/admin/reports/csat', 'Escalated/Admin/Reports/CsatReport')
    props = page['props']

    expect(props['csat_average']).to eq(4.0)
    expect(props['total_ratings']).to eq(2)
    expect(props['response_rate']).to eq(50.0)
    expect(props['by_agent'].sole).to include('agent_id' => agent.id, 'agent_name' => 'Grace Agent',
                                              'avg_rating' => 4.0, 'total_ratings' => 2)
    expect(props['over_time'].pluck('value')).to eq([5.0, 3.0])
    expect(props['over_time']).to all(include('label'))
  end

  describe 'agent detail' do
    it 'renders an agent against the period before' do # rubocop:disable RSpec/ExampleLength
      current = ticket(created: 2.days, response_hours: 2, resolution_hours: 8)
      ticket(created: 1.day, response_hours: 4)
      ticket(created: 40.days, response_hours: 1, resolution_hours: 1)
      ticket(created: 3.days, assignee: admin, response_hours: 9)
      rate(current, 4)
      Escalated::Reply.create!(ticket: current, body: 'On it.', author: agent, created_at: 1.day.ago)

      page = expect_screen("/support/admin/reports/agent/#{agent.id}/detail",
                           'Escalated/Admin/Reports/AgentDetail')
      props = page['props']

      expect(props['agent']).to include('id' => agent.id, 'name' => 'Grace Agent', 'email' => 'grace@example.test')
      expect(props).to include(
        'period_days' => 30, 'total_tickets' => 2, 'resolved_tickets' => 1, 'avg_frt' => 3.0,
        'avg_resolution' => 8.0, 'csat_score' => 4.0,
        'prev_total_tickets' => 1, 'prev_resolved_tickets' => 1, 'prev_avg_frt' => 1.0,
        'prev_avg_resolution' => 1.0, 'prev_csat_score' => nil
      )
      expect(props['response_percentiles'].keys).to eq(%w[p50 p75 p90 p95 p99])
      expect(props['response_percentiles']['p50']).to eq(3.0)
      expect(props['workload'].sum { |d| d['value'] }).to eq(2)
      expect(props['productivity'].sum { |d| d['value'] }).to eq(2)
      expect(props['productivity']).to all(include('label', 'values'))
      expect(props['csat_breakdown']).to eq([{ 'label' => '4 stars', 'value' => 1 }])
    end

    it 'is not found for someone who is not a user' do
      get '/support/admin/reports/agent/999999/detail'

      expect(response).to have_http_status(:not_found)
    end
  end
end
