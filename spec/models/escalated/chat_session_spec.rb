# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::ChatSession do
  describe 'associations' do
    it { is_expected.to belong_to(:ticket).class_name('Escalated::Ticket') }
    it { is_expected.to belong_to(:agent).class_name('User').optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:customer_session_id) }
    it { is_expected.to validate_presence_of(:status) }

    it {
      expect(described_class.new).to validate_inclusion_of(:status).in_array(%w[waiting active ended transferred])
    }

    it 'validates rating is between 1 and 5' do
      session = build(:escalated_chat_session, rating: 6)
      expect(session).not_to be_valid
    end

    it 'allows nil rating' do
      session = build(:escalated_chat_session, rating: nil)
      expect(session).to be_valid
    end
  end

  describe 'scopes' do
    let!(:waiting_session) { create(:escalated_chat_session, :waiting) }
    let!(:active_session) { create(:escalated_chat_session, :active) }
    let!(:ended_session) { create(:escalated_chat_session, :ended) }

    it 'returns waiting sessions' do
      expect(described_class.waiting).to include(waiting_session)
      expect(described_class.waiting).not_to include(active_session)
    end

    it 'returns active sessions' do
      expect(described_class.active).to include(active_session)
      expect(described_class.active).not_to include(waiting_session)
    end

    it 'returns ended sessions' do
      expect(described_class.ended).to include(ended_session)
      expect(described_class.ended).not_to include(active_session)
    end

    it 'filters by agent' do
      expect(described_class.for_agent(active_session.agent_id)).to include(active_session)
    end
  end

  describe '#duration' do
    it 'returns nil when not started' do
      session = build(:escalated_chat_session, started_at: nil)
      expect(session.duration).to be_nil
    end

    it 'calculates duration for active session' do
      session = build(:escalated_chat_session, started_at: 30.minutes.ago, ended_at: nil)
      expect(session.duration).to be_within(5).of(1800)
    end

    it 'calculates duration for ended session' do
      session = build(:escalated_chat_session, started_at: 1.hour.ago, ended_at: 30.minutes.ago)
      expect(session.duration).to be_within(5).of(1800)
    end
  end

  describe 'status helpers' do
    it 'returns true for waiting?' do
      session = build(:escalated_chat_session, status: 'waiting')
      expect(session).to be_waiting
    end

    it 'returns true for active?' do
      session = build(:escalated_chat_session, status: 'active')
      expect(session).to be_active
    end

    it 'returns true for ended?' do
      session = build(:escalated_chat_session, status: 'ended')
      expect(session).to be_ended
    end
  end
end
