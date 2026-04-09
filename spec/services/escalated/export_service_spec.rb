# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::ExportService do
  let(:from) { 30.days.ago.beginning_of_day }
  let(:to) { Time.current.end_of_day }
  let(:service) { described_class.new(from: from, to: to) }

  let(:agent) { create(:user) }

  before do
    create(:escalated_ticket,
           assigned_to: agent.id,
           first_response_at: 2.hours.ago,
           resolved_at: 1.hour.ago,
           created_at: 5.days.ago)
  end

  describe '#export_csv' do
    Escalated::ExportService::EXPORTABLE_REPORTS.each do |report_type|
      it "exports #{report_type} as CSV" do
        result = service.export_csv(report_type)
        expect(result).to be_a(String)
      end
    end

    it 'raises for unknown report type' do
      expect { service.export_csv('nonexistent') }.to raise_error(ArgumentError)
    end
  end

  describe '#export_json' do
    Escalated::ExportService::EXPORTABLE_REPORTS.each do |report_type|
      it "exports #{report_type} as JSON" do
        result = service.export_json(report_type)
        expect { JSON.parse(result) }.not_to raise_error
      end
    end

    it 'raises for unknown report type' do
      expect { service.export_json('nonexistent') }.to raise_error(ArgumentError)
    end
  end

  describe '#export_cohort_csv' do
    %w[department channel type].each do |dimension|
      it "exports #{dimension} cohort as CSV" do
        result = service.export_cohort_csv(dimension)
        expect(result).to be_a(String)
      end
    end
  end

  describe '#export_cohort_json' do
    %w[department channel type].each do |dimension|
      it "exports #{dimension} cohort as JSON" do
        result = service.export_cohort_json(dimension)
        expect { JSON.parse(result) }.not_to raise_error
      end
    end
  end
end
