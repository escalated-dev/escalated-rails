# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::ChatRoutingRule do
  describe 'associations' do
    it { is_expected.to belong_to(:department).class_name('Escalated::Department').optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:routing_strategy) }
    it { is_expected.to validate_presence_of(:offline_behavior) }

    it {
      expect(described_class.new).to validate_inclusion_of(:routing_strategy)
        .in_array(%w[round_robin least_busy random skills_based])
    }

    it {
      expect(described_class.new).to validate_inclusion_of(:offline_behavior)
        .in_array(%w[show_form hide_widget show_message])
    }

    it { is_expected.to validate_numericality_of(:max_queue_size).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:max_concurrent_per_agent).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:auto_close_after_minutes).is_greater_than(0) }
  end

  describe 'scopes' do
    let!(:active_rule) { create(:escalated_chat_routing_rule) }
    let!(:inactive_rule) { create(:escalated_chat_routing_rule, :inactive) }

    it 'returns active rules' do
      expect(described_class.active).to include(active_rule)
      expect(described_class.active).not_to include(inactive_rule)
    end

    it 'orders by position' do
      rule_b = create(:escalated_chat_routing_rule, position: 2)
      rule_a = create(:escalated_chat_routing_rule, position: 1)
      expect(described_class.ordered.to_a.last(2)).to eq([rule_a, rule_b])
    end
  end

  describe '#active?' do
    it 'returns true when is_active is true' do
      rule = build(:escalated_chat_routing_rule, is_active: true)
      expect(rule).to be_active
    end

    it 'returns false when is_active is false' do
      rule = build(:escalated_chat_routing_rule, is_active: false)
      expect(rule).not_to be_active
    end
  end
end
