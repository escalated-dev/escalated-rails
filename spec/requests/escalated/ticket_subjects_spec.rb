# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Ticket subject endpoints', type: :request do
  let(:agent) { create(:user, :agent, email: 'agent-subjects@example.test') }
  let(:ticket) { create(:escalated_ticket) }

  before do
    allow(Escalated.configuration).to receive(:notification_channels).and_return([])
    ActiveRecord::Base.connection.create_table(:fake_projects, id: false, force: true) do |t|
      t.string :id, primary_key: true
      t.string :name, null: false
      t.string :account
    end
    Escalated.configure { |c| c.ticket_subject_types = [FakeProject.name] }
    agent
    ticket
  end

  after do
    ActiveRecord::Base.connection.drop_table(:fake_projects, if_exists: true)
    Escalated.configure { |c| c.ticket_subject_types = [] }
  end

  def sign_in_as(user)
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Escalated::ApplicationController).to receive(:current_user).and_return(user)
    # rubocop:enable RSpec/AnyInstance
  end

  describe 'POST /support/agent/tickets/:id/subjects' do
    it 'attaches an allowlisted subject' do
      FakeProject.create!(id: 'p1', name: 'Acme', account: 'Acme Co')
      sign_in_as(agent)

      post "/support/agent/tickets/#{ticket.id}/subjects",
           params: { type: 'FakeProject', subject_id: 'p1', role: 'project' },
           as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['subject']).to include(
        'type' => 'FakeProject',
        'id' => 'p1',
        'role' => 'project',
        'title' => 'Acme'
      )
      expect(ticket.ticket_subjects.count).to eq(1)
    end

    it 'rejects types outside the allowlist' do
      sign_in_as(agent)

      post "/support/agent/tickets/#{ticket.id}/subjects",
           params: { type: 'UnknownModel', subject_id: '1' },
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['errors']['type'].first).to include('not an allowed ticket subject')
    end

    it 'rejects when the allowlist is empty' do
      Escalated.configure { |c| c.ticket_subject_types = [] }
      sign_in_as(agent)

      post "/support/agent/tickets/#{ticket.id}/subjects",
           params: { type: 'FakeProject', subject_id: 'p1' },
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to include('not configured')
    end
  end

  describe 'DELETE /support/agent/tickets/:id/subjects/:subject_id' do
    it 'removes a subject link' do
      project = FakeProject.create!(id: 'p1', name: 'Acme')
      link = ticket.attach_subject(project)
      sign_in_as(agent)

      delete "/support/agent/tickets/#{ticket.id}/subjects/#{link.id}", as: :json

      expect(response).to have_http_status(:ok)
      expect(ticket.ticket_subjects.count).to eq(0)
    end
  end

  describe 'POST /support/admin/tickets/:id/subjects' do
    let(:admin) { create(:user, :admin, email: 'admin-subjects@example.test') }

    it 'attaches for admins' do
      FakeProject.create!(id: 'p1', name: 'Acme')
      sign_in_as(admin)

      post "/support/admin/tickets/#{ticket.id}/subjects",
           params: { subject: { type: 'FakeProject', id: 'p1', role: 'account' } },
           as: :json

      expect(response).to have_http_status(:created)
      expect(ticket.ticket_subjects.first.role).to eq('account')
    end
  end
end
