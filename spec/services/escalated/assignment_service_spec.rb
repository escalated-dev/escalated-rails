# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Services::AssignmentService do
  describe '.auto_assign' do
    let(:department) { create(:escalated_department) }

    def add_agent(chat_status:)
      agent = create(:user, :agent)
      department.agents << agent
      create(:escalated_agent_profile, user: agent, chat_status: chat_status)
      agent
    end

    it 'skips offline agents and assigns to an available one' do
      # The offline agent carries the lighter load, so a load-only round-robin
      # would route to it. Availability filtering must take precedence (issue #67).
      add_agent(chat_status: 'offline')
      online = add_agent(chat_status: 'online')

      # Give the online agent an existing open ticket so it is strictly the
      # heavier-loaded candidate; the offline agent has none.
      create(:escalated_ticket, department: department, assigned_to: online.id, status: :in_progress)

      ticket = create(:escalated_ticket, department: department)

      result = described_class.auto_assign(ticket)

      expect(result).to eq(online)
      expect(ticket.reload.assigned_to).to eq(online.id)
    end

    it 'treats "away" agents as available' do
      add_agent(chat_status: 'offline')
      away = add_agent(chat_status: 'away')

      ticket = create(:escalated_ticket, department: department)

      expect(described_class.auto_assign(ticket)).to eq(away)
    end

    it 'still assigns when every agent is offline so tickets are not stranded' do
      offline_a = add_agent(chat_status: 'offline')
      offline_b = add_agent(chat_status: 'offline')

      ticket = create(:escalated_ticket, department: department)

      result = described_class.auto_assign(ticket)

      expect(result).to be_present
      expect([offline_a.id, offline_b.id]).to include(ticket.reload.assigned_to)
    end
  end
end
