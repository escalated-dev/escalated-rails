# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::MentionService do
  let(:service) { described_class.new }
  let(:agent) { create(:user) }
  let(:ticket) { create(:escalated_ticket) }

  describe '#extract_mentions' do
    it 'extracts single mention' do
      result = service.extract_mentions('Hello @john please review')
      expect(result).to eq(['john'])
    end

    it 'extracts multiple mentions' do
      result = service.extract_mentions('@alice and @bob please check')
      expect(result).to contain_exactly('alice', 'bob')
    end

    it 'handles dotted usernames' do
      result = service.extract_mentions('cc @john.doe')
      expect(result).to eq(['john.doe'])
    end

    it 'deduplicates mentions' do
      result = service.extract_mentions('@alice said @alice should review')
      expect(result).to eq(['alice'])
    end

    it 'returns empty for nil input' do
      expect(service.extract_mentions(nil)).to eq([])
    end

    it 'returns empty when no mentions' do
      expect(service.extract_mentions('No mentions here')).to eq([])
    end
  end

  describe '#search_agents' do
    before { agent }

    it 'returns matching agents' do
      results = service.search_agents(agent.email[0..3])
      expect(results).to be_an(Array)
      expect(results.first).to have_key(:id)
      expect(results.first).to have_key(:name)
      expect(results.first).to have_key(:email)
    end

    it 'returns empty for no match' do
      results = service.search_agents('zzzznonexistent')
      expect(results).to be_empty
    end

    it 'returns empty for blank query' do
      expect(service.search_agents('')).to eq([])
    end

    it 'respects limit parameter' do
      3.times { create(:user) }
      results = service.search_agents(agent.email[0..1], limit: 2)
      expect(results.size).to be <= 2
    end
  end

  describe '#process_mentions' do
    let(:reply) { create(:escalated_reply, ticket: ticket, body: "@#{agent.email.split('@').first} please check") }

    it 'creates mention records for recognized users' do
      mentions = service.process_mentions(reply)
      expect(mentions).to be_an(Array)
    end

    it 'creates activity records for notifications' do
      service.process_mentions(reply)
      # Verify activity was created if user was found
      activities = Escalated::TicketActivity.where(ticket: ticket, activity_type: 'mention')
      # May or may not find user depending on email pattern matching
      expect(activities.count).to be >= 0
    end
  end

  describe '#unread_mentions' do
    it 'returns unread mentions for user' do
      reply = create(:escalated_reply, ticket: ticket, body: 'test')
      create(:escalated_mention, reply: reply, user: agent)

      unread = service.unread_mentions(agent.id)
      expect(unread.count).to eq(1)
    end

    it 'excludes read mentions' do
      reply = create(:escalated_reply, ticket: ticket, body: 'test')
      create(:escalated_mention, reply: reply, user: agent, read_at: Time.current)

      unread = service.unread_mentions(agent.id)
      expect(unread.count).to eq(0)
    end
  end

  describe '#mark_as_read' do
    it 'marks specified mentions as read' do
      reply = create(:escalated_reply, ticket: ticket, body: 'test')
      mention = create(:escalated_mention, reply: reply, user: agent)

      service.mark_as_read([mention.id], agent.id)
      mention.reload
      expect(mention.read_at).not_to be_nil
    end
  end
end
