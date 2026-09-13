# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Workflow do
  # The events NotificationService actually dispatches that WorkflowSubscriber
  # maps to a trigger. sla_warning is mapped but nothing dispatches it.
  fired = %w[ticket.created ticket.status_changed ticket.assigned ticket.priority_changed
             ticket.replied ticket.escalated sla.breached]

  describe 'trigger_event' do
    fired.each do |event|
      it "accepts #{event}, which the subscriber fires" do
        expect(build(:escalated_workflow, trigger_event: event)).to be_valid
      end
    end

    %w[ticket.updated ticket.tagged ticket.department_changed reply.created reply.agent_reply
       sla.warning ticket.reopened].each do |event|
      it "refuses #{event}, which nothing fires" do
        workflow = build(:escalated_workflow, trigger_event: event)

        expect(workflow).not_to be_valid
        expect(workflow.errors[:trigger_event]).to be_present
      end
    end

    it 'offers the form exactly the triggers the subscriber fires' do
      expect(described_class::TRIGGER_EVENTS).to match_array(
        %w[ticket.created ticket.status_changed ticket.assigned ticket.priority_changed
           ticket.replied ticket.escalated sla.breached]
      )
      expect(described_class::TRIGGER_EVENTS - Escalated::Services::WorkflowSubscriber::EVENT_MAP.values).to be_empty
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
