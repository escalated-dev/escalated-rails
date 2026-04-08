# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Services::TicketService, '.split' do
  let(:user) { create(:user) }
  let(:ticket) do
    t = create(:escalated_ticket, :with_department, priority: :high, requester: user, department: department)
    t.tags << tag1
    t.tags << tag2
    t
  end
  let(:reply) do
    create(:escalated_reply, ticket: ticket, author: user, body: 'I have a separate issue with billing.')
  end
  let(:agent) { create(:user, :agent) }
  let(:department) { create(:escalated_department) }
  let(:tag1) { create(:escalated_tag) }
  let(:tag2) { create(:escalated_tag) }

  before do
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)
  end



  describe '.split' do
    it 'creates a new ticket from the reply' do
      expect { described_class.split(ticket, reply, actor: agent) }
        .to change(Escalated::Ticket, :count).by(1)
    end

    it 'returns the new ticket' do
      new_ticket = described_class.split(ticket, reply, actor: agent)
      expect(new_ticket).to be_a(Escalated::Ticket)
      expect(new_ticket).to be_persisted
    end

    it 'sets the description from the reply body' do
      new_ticket = described_class.split(ticket, reply, actor: agent)
      expect(new_ticket.description).to eq(reply.body)
    end

    it 'copies the requester from the original ticket' do
      new_ticket = described_class.split(ticket, reply, actor: agent)
      expect(new_ticket.requester).to eq(user)
    end

    it 'copies the priority from the original ticket' do
      new_ticket = described_class.split(ticket, reply, actor: agent)
      expect(new_ticket.priority).to eq('high')
    end

    it 'copies the department from the original ticket' do
      new_ticket = described_class.split(ticket, reply, actor: agent)
      expect(new_ticket.department_id).to eq(department.id)
    end

    it 'copies tags from the original ticket' do
      new_ticket = described_class.split(ticket, reply, actor: agent)
      expect(new_ticket.tags).to include(tag1, tag2)
    end

    it 'creates a parent_child link between the tickets' do
      new_ticket = described_class.split(ticket, reply, actor: agent)
      link = Escalated::TicketLink.find_by(parent_ticket: ticket, child_ticket: new_ticket)
      expect(link).to be_present
      expect(link.link_type).to eq('parent_child')
    end

    it 'adds a system note to the original ticket' do
      new_ticket = described_class.split(ticket, reply, actor: agent)
      system_note = ticket.replies.where(is_system: true).last
      expect(system_note.body).to include(new_ticket.reference)
      expect(system_note.body).to include('split into')
    end

    it 'adds a system note to the new ticket' do
      new_ticket = described_class.split(ticket, reply, actor: agent)
      system_note = new_ticket.replies.where(is_system: true).last
      expect(system_note.body).to include(ticket.reference)
      expect(system_note.body).to include('split from')
    end

    it 'stores split_from in metadata' do
      new_ticket = described_class.split(ticket, reply, actor: agent)
      expect(new_ticket.metadata['split_from']).to eq(ticket.reference)
    end

    it 'generates a unique reference for the new ticket' do
      new_ticket = described_class.split(ticket, reply, actor: agent)
      expect(new_ticket.reference).to be_present
      expect(new_ticket.reference).not_to eq(ticket.reference)
    end
  end
end
