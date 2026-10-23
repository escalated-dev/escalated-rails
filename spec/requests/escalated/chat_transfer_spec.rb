# frozen_string_literal: true

require 'rails_helper'

# POST /support/admin/chat/:id/transfer (escalated-laravel
# escalated.admin.chat.transfer). The shared ChatActionBar posts
# {"agent_id"} or {"department_id"}; the ticket view offers departments.
# The older {"type", "id"} body is read too.
RSpec.describe 'Live chat transfer' do
  let(:agent) { create(:user, :agent) }
  let(:other) { create(:user, :agent) }
  let(:billing) { create(:escalated_department) }
  let(:session) { create(:escalated_chat_session, :active, agent: agent) }

  before do
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(agent)
    allow(Escalated::TicketAccess).to receive(:eligible_agent?).and_return(true)
    allow(Escalated::Services::ChatRoutingService).to receive(:find_available_agent).and_return(nil)
  end

  def transfer(body)
    post "/support/admin/chat/#{session.id}/transfer", params: body.to_json,
                                                       headers: { 'CONTENT_TYPE' => 'application/json',
                                                                  'ACCEPT' => 'application/json' }
  end

  it 'moves the ticket to a department and puts the chat back in the queue' do
    transfer(department_id: billing.id)

    expect(response).to have_http_status(:ok)
    session.reload
    expect(session.status).to eq('waiting')
    expect(session.agent_id).to be_nil
    expect(session.ticket.department_id).to eq(billing.id)
    expect(session.ticket.assigned_to).to be_nil
    expect(Escalated::Services::ChatRoutingService).to have_received(:find_available_agent)
      .with(department_id: billing.id, ticket: session.ticket)
  end

  it 'routes the requeued chat to an available agent in the new department' do
    allow(Escalated::Services::ChatRoutingService).to receive(:find_available_agent).and_return(other.id)

    transfer(department_id: billing.id)

    session.reload
    expect(session.status).to eq('active')
    expect(session.agent_id).to eq(other.id)
    expect(session.ticket.department_id).to eq(billing.id)
  end

  it 'does both for an agent and a department' do
    transfer(agent_id: other.id, department_id: billing.id)

    expect(response).to have_http_status(:ok)
    session.reload
    expect(session.agent_id).to eq(other.id)
    expect(session.status).to eq('active')
    expect(session.ticket.department_id).to eq(billing.id)
    expect(session.ticket.assigned_to).to eq(other.id)
  end

  it 'still transfers to an agent alone' do
    transfer(agent_id: other.id)

    expect(response).to have_http_status(:ok)
    expect(session.reload.agent_id).to eq(other.id)
  end

  it 'reads the type and id body' do
    transfer(type: 'department', id: billing.id)

    expect(response).to have_http_status(:ok)
    expect(session.reload.ticket.department_id).to eq(billing.id)
  end

  it 'refuses no target and an unknown department' do
    transfer({})
    expect(response).to have_http_status(:unprocessable_content)

    transfer(department_id: 999_999)
    expect(response).to have_http_status(:unprocessable_content)

    session.reload
    expect(session.agent_id).to eq(agent.id)
    expect(session.status).to eq('active')
  end
end
