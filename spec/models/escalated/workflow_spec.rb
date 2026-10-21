# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Workflow do
  describe 'trigger_event' do
    Escalated::EventNames::EMITTED.each do |event|
      it "accepts #{event}, which the subscriber fires" do
        expect(build(:escalated_workflow, trigger_event: event)).to be_valid
      end
    end

    %w[reply.agent_reply ticket.merged ticket_created].each do |event|
      it "refuses #{event}, which nothing fires" do
        workflow = build(:escalated_workflow, trigger_event: event)

        expect(workflow).not_to be_valid
        expect(workflow.errors[:trigger_event]).to be_present
      end
    end

    it 'stores a legacy trigger under its canonical name' do
      workflow = create(:escalated_workflow, trigger_event: 'ticket.replied')

      expect(workflow.reload.trigger_event).to eq('reply.created')
    end

    it 'offers the form exactly the canonical events this engine emits' do
      expect(described_class::TRIGGER_EVENTS).to match_array(Escalated::EventNames::EMITTED)
      expect(described_class::TRIGGER_EVENTS & Escalated::EventNames::LEGACY.keys).to be_empty
    end
  end

  describe 'conditions' do
    it 'defaults omitted conditions to an empty all, which matches every ticket' do
      workflow = build(:escalated_workflow, conditions: nil)

      expect(workflow).to be_valid
      expect(workflow.conditions).to eq('all' => [])
    end

    it 'accepts a stored flat list of conditions' do
      expect(build(:escalated_workflow, conditions: [{ 'field' => 'status', 'value' => 'open' }])).to be_valid
    end

    it 'refuses an object carrying both all and any' do
      workflow = build(:escalated_workflow, conditions: { 'all' => [], 'any' => [] })

      expect(workflow).not_to be_valid
      expect(workflow.errors[:conditions]).to be_present
    end
  end

  describe 'actions' do
    it 'requires at least one action' do
      workflow = build(:escalated_workflow, actions: [])

      expect(workflow).not_to be_valid
      expect(workflow.errors[:actions]).to be_present
    end
  end
end
