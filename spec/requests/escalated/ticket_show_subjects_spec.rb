# frozen_string_literal: true

require 'rails_helper'

# The sidebar's Related card reads `ticket.subjects`. The agent and admin
# ticket pages send them in the same shape as the API ticket resource.
RSpec.describe 'Ticket subjects on the ticket pages', type: :request do
  let(:agent) { create(:user, :agent, email: 'show-subjects-agent@example.test') }
  let(:admin) { create(:user, :admin, email: 'show-subjects-admin@example.test') }
  let(:ticket) { create(:escalated_ticket, assignee: agent) }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    Escalated.configure { |c| c.ticket_subject_types = [FakeProject.name] }
    ticket.attach_subject(FakeProject.create!(id: 'p9', name: 'Acme', account: 'Acme Co'), role: 'project')
  end

  after { Escalated.configure { |c| c.ticket_subject_types = [] } }

  def sign_in_as(user)
    # rubocop:disable-next RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)
  end

  def expected_subjects
    JSON.parse(Escalated::TicketSerializer.subjects_for(ticket.reload).to_json)
  end

  it 'sends them on the agent ticket page' do
    sign_in_as(agent)
    get "/support/agent/tickets/#{ticket.reference}"

    subjects = inertia_page.dig('props', 'ticket', 'subjects')
    expect(subjects).to eq(expected_subjects)
    expect(subjects.first).to include('type' => 'FakeProject', 'id' => 'p9', 'role' => 'project', 'title' => 'Acme')
  end

  it 'sends them on the admin ticket page' do
    sign_in_as(admin)
    get "/support/admin/tickets/#{ticket.reference}"

    expect(inertia_page.dig('props', 'ticket', 'subjects')).to eq(expected_subjects)
  end
end
