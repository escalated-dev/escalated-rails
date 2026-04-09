# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::ReportingService do
  let(:from) { 30.days.ago.beginning_of_day }
  let(:to) { Time.current.end_of_day }
  let(:service) { described_class.new(from: from, to: to) }

  let(:agent) { create(:user) }
  let(:department) { create(:escalated_department) }
  let(:tag) { create(:escalated_tag, name: 'billing') }

  let(:ticket1) do
    create(:escalated_ticket,
           assigned_to: agent.id,
           department: department,
           first_response_at: 2.hours.ago,
           resolved_at: 1.hour.ago,
           channel: 'email',
           ticket_type: 'question',
           created_at: 5.days.ago)
  end

  let(:ticket2) do
    create(:escalated_ticket,
           assigned_to: agent.id,
           department: department,
           first_response_at: 4.hours.ago,
           resolved_at: nil,
           sla_breached: true,
           channel: 'chat',
           ticket_type: 'incident',
           created_at: 3.days.ago)
  end

  let(:ticket3) do
    create(:escalated_ticket,
           assigned_to: nil,
           first_response_at: nil,
           resolved_at: nil,
           created_at: 1.day.ago)
  end

  before do
    ticket1.tags << tag
    ticket2
    ticket3
  end

  describe '#sla_breach_trends' do
    it 'returns daily breach data' do
      result = service.sla_breach_trends
      expect(result).to be_an(Array)
      expect(result.first).to have_key(:date)
      expect(result.first).to have_key(:total_breaches)
    end
  end

  describe '#frt_distribution' do
    it 'returns distribution with buckets and percentiles' do
      result = service.frt_distribution
      expect(result).to have_key(:buckets)
      expect(result).to have_key(:stats)
      expect(result).to have_key(:percentiles)
    end

    it 'includes p50 through p99 percentiles' do
      result = service.frt_distribution
      if result[:percentiles].any?
        expect(result[:percentiles]).to have_key(:p50)
        expect(result[:percentiles]).to have_key(:p75)
        expect(result[:percentiles]).to have_key(:p90)
        expect(result[:percentiles]).to have_key(:p95)
        expect(result[:percentiles]).to have_key(:p99)
      end
    end
  end

  describe '#frt_trends' do
    it 'returns daily FRT averages' do
      result = service.frt_trends
      expect(result).to be_an(Array)
      expect(result.first).to have_key(:date)
      expect(result.first).to have_key(:avg_hours)
    end
  end

  describe '#frt_by_agent' do
    it 'returns FRT grouped by agent' do
      result = service.frt_by_agent
      expect(result).to be_an(Array)
      agent_data = result.find { |r| r[:agent_id] == agent.id }
      expect(agent_data).not_to be_nil
      expect(agent_data).to have_key(:avg_hours)
      expect(agent_data).to have_key(:percentiles)
    end
  end

  describe '#resolution_time_distribution' do
    it 'returns resolution time distribution' do
      result = service.resolution_time_distribution
      expect(result).to have_key(:stats)
      expect(result[:stats][:count]).to be >= 1
    end
  end

  describe '#resolution_time_trends' do
    it 'returns daily resolution time averages' do
      result = service.resolution_time_trends
      expect(result).to be_an(Array)
    end
  end

  describe '#agent_performance_ranking' do
    it 'ranks agents by composite score' do
      result = service.agent_performance_ranking
      expect(result).to be_an(Array)
      agent_data = result.find { |r| r[:agent_id] == agent.id }
      expect(agent_data).not_to be_nil
      expect(agent_data).to have_key(:composite_score)
      expect(agent_data).to have_key(:resolution_rate)
      expect(agent_data[:composite_score]).to be_a(Numeric)
    end
  end

  describe '#cohort_analysis' do
    it 'analyzes by department' do
      result = service.cohort_analysis(dimension: 'department')
      expect(result).to be_an(Array)
      dept_data = result.find { |r| r[:name] == department.name }
      expect(dept_data).not_to be_nil
      expect(dept_data[:total]).to be >= 1
    end

    it 'analyzes by tag' do
      result = service.cohort_analysis(dimension: 'tag')
      expect(result).to be_an(Array)
    end

    it 'analyzes by channel' do
      result = service.cohort_analysis(dimension: 'channel')
      expect(result).to be_an(Array)
    end

    it 'analyzes by type' do
      result = service.cohort_analysis(dimension: 'type')
      expect(result).to be_an(Array)
    end

    it 'returns error for unknown dimension' do
      result = service.cohort_analysis(dimension: 'unknown')
      expect(result).to have_key(:error)
    end
  end

  describe '#period_comparison' do
    it 'compares current vs previous period' do
      result = service.period_comparison
      expect(result).to have_key(:current)
      expect(result).to have_key(:previous)
      expect(result).to have_key(:changes)
      expect(result[:current]).to have_key(:total_created)
      expect(result[:changes]).to have_key(:total_created)
    end
  end
end
