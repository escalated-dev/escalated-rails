# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Ticket subjects', type: :model do
  before do
    ActiveRecord::Base.connection.create_table(:fake_projects, id: false, force: true) do |t|
      t.string :id, primary_key: true
      t.string :name, null: false
      t.string :account
    end

    Escalated.configure do |config|
      config.ticket_subject_types = [FakeProject.name]
    end
  end

  after do
    ActiveRecord::Base.connection.drop_table(:fake_projects, if_exists: true)
    Escalated.configure do |config|
      config.ticket_subject_types = []
    end
  end

  describe 'attach, detach, and sync' do
    let(:ticket) { create(:escalated_ticket) }

    it 'attaches a host model as a ticket subject, preserving a string key' do
      project = FakeProject.create!(id: 'prj_9f1c', name: 'Acme Redesign', account: 'Acme')

      link = ticket.attach_subject(project, role: 'project')

      expect(link).to be_a(Escalated::TicketSubject)
      expect(ticket.ticket_subjects.count).to eq(1)
      expect(link.subject_type).to eq('FakeProject')
      expect(link.subject_id).to eq('prj_9f1c')
      expect(link.role).to eq('project')
      expect(link.subject).to eq(project)
    end

    it 'is idempotent on the ticket+type+id key and updates the role' do
      project = FakeProject.create!(id: 'p1', name: 'A')

      ticket.attach_subject(project)
      ticket.attach_subject(project, role: 'account')

      expect(ticket.ticket_subjects.count).to eq(1)
      expect(ticket.ticket_subjects.first.role).to eq('account')
    end

    it 'serializes subjects through the presentation contract' do
      project = FakeProject.create!(id: '7', name: 'Acme Redesign', account: 'Acme')
      ticket.attach_subject(project, role: 'project')

      subjects = Escalated::TicketSerializer.subjects_for(ticket.reload)

      expect(subjects.length).to eq(1)
      expect(subjects.first).to include(
        type: 'FakeProject',
        id: '7',
        role: 'project',
        title: 'Acme Redesign',
        subtitle: 'Project · Acme',
        url: 'https://app.test/projects/7',
        color: '#2563eb',
        icon: 'folder',
        missing: false
      )
    end

    it 'marks missing subjects when the host record was deleted' do
      project = FakeProject.create!(id: 'gone', name: 'Gone')
      ticket.attach_subject(project)
      project.delete

      payload = Escalated::TicketSerializer.subjects_for(ticket.reload).first

      expect(payload[:missing]).to be(true)
      expect(payload[:title]).to eq('FakeProject #gone')
    end

    it 'detaches a subject' do
      project = FakeProject.create!(id: '1', name: 'A')
      ticket.attach_subject(project)

      expect(ticket.detach_subject(project)).to eq(1)
      expect(ticket.ticket_subjects.count).to eq(0)
    end

    it 'syncs subjects, replacing existing and preserving order' do
      a = FakeProject.create!(id: 'a', name: 'A')
      b = FakeProject.create!(id: 'b', name: 'B')
      c = FakeProject.create!(id: 'c', name: 'C')

      ticket.attach_subject(a)
      ticket.sync_subjects([[b, 'primary'], c])

      links = ticket.ticket_subjects.order(:position).to_a
      expect(links.length).to eq(2)
      expect(links[0].subject_id).to eq('b')
      expect(links[0].role).to eq('primary')
      expect(links[0].position).to eq(0)
      expect(links[1].subject_id).to eq('c')
      expect(links[1].position).to eq(1)
    end

    it 'rejects attaching a type outside the configured allowlist' do
      Escalated.configure { |c| c.ticket_subject_types = ['App::Models::SomethingElse'] }
      project = FakeProject.create!(id: '1', name: 'A')

      expect { ticket.attach_subject(project) }.to raise_error(ArgumentError, /not an allowed ticket subject/)
    end

    it 'allows any model programmatically when no allowlist is configured' do
      Escalated.configure { |c| c.ticket_subject_types = [] }
      project = FakeProject.create!(id: '1', name: 'A')

      expect(ticket.attach_subject(project)).to be_a(Escalated::TicketSubject)
    end
  end
end
