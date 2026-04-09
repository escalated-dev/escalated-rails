# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::WorkflowEngine do
  let(:engine) { described_class.new }
  let(:agent) { create(:user) }
  let(:department) { create(:escalated_department) }
  let(:ticket) do
    create(:escalated_ticket, status: :open, priority: :medium, assigned_to: agent.id, department: department)
  end

  describe '#evaluate_conditions' do
    it 'evaluates AND conditions (all)' do
      conditions = { 'all' => [
        { 'field' => 'status', 'operator' => 'equals', 'value' => 'open' },
        { 'field' => 'priority', 'operator' => 'equals', 'value' => 'medium' }
      ] }
      expect(engine.evaluate_conditions(conditions, ticket)).to be true
    end

    it 'evaluates OR conditions (any)' do
      conditions = { 'any' => [
        { 'field' => 'status', 'operator' => 'equals', 'value' => 'closed' },
        { 'field' => 'priority', 'operator' => 'equals', 'value' => 'medium' }
      ] }
      expect(engine.evaluate_conditions(conditions, ticket)).to be true
    end

    it 'returns false when AND conditions do not match' do
      conditions = { 'all' => [
        { 'field' => 'status', 'operator' => 'equals', 'value' => 'closed' },
        { 'field' => 'priority', 'operator' => 'equals', 'value' => 'medium' }
      ] }
      expect(engine.evaluate_conditions(conditions, ticket)).to be false
    end

    it 'supports contains operator' do
      conditions = { 'all' => [
        { 'field' => 'subject', 'operator' => 'contains', 'value' => ticket.subject[0..3] }
      ] }
      expect(engine.evaluate_conditions(conditions, ticket)).to be true
    end

    it 'supports not_equals operator' do
      conditions = { 'all' => [
        { 'field' => 'status', 'operator' => 'not_equals', 'value' => 'closed' }
      ] }
      expect(engine.evaluate_conditions(conditions, ticket)).to be true
    end

    it 'supports is_empty operator' do
      ticket.update!(ticket_type: nil)
      conditions = { 'all' => [
        { 'field' => 'ticket_type', 'operator' => 'is_empty', 'value' => '' }
      ] }
      expect(engine.evaluate_conditions(conditions, ticket)).to be true
    end

    it 'supports greater_than operator for numeric fields' do
      conditions = { 'all' => [
        { 'field' => 'hours_since_created', 'operator' => 'greater_or_equal', 'value' => '0' }
      ] }
      expect(engine.evaluate_conditions(conditions, ticket)).to be true
    end
  end

  describe '#process_event' do
    let!(:workflow) do
      create(:escalated_workflow,
             trigger_event: 'ticket.created',
             conditions: { 'all' => [{ 'field' => 'status', 'operator' => 'equals', 'value' => 'open' }] },
             actions: [{ 'type' => 'change_priority', 'value' => 'high' }])
    end

    it 'executes matching workflow actions' do
      engine.process_event('ticket.created', ticket)
      ticket.reload
      expect(ticket.priority).to eq('high')
    end

    it 'creates a workflow log on execution' do
      expect { engine.process_event('ticket.created', ticket) }
        .to change(Escalated::WorkflowLog, :count).by(1)
    end

    it 'logs skipped status for non-matching conditions' do
      ticket.update!(status: :closed)
      engine.process_event('ticket.created', ticket)
      log = Escalated::WorkflowLog.last
      expect(log.status).to eq('skipped')
    end
  end

  describe '#dry_run' do
    let(:workflow) do
      create(:escalated_workflow,
             trigger_event: 'ticket.created',
             conditions: { 'all' => [{ 'field' => 'status', 'operator' => 'equals', 'value' => 'open' }] },
             actions: [{ 'type' => 'add_note', 'value' => 'Auto note for {{reference}}' }])
    end

    it 'returns match status and action preview without executing' do
      result = engine.dry_run(workflow, ticket)
      expect(result[:matched]).to be true
      expect(result[:actions].first[:value]).to include(ticket.reference)
      expect(ticket.replies.count).to eq(0)
    end
  end

  describe '#process_delayed_actions' do
    it 'executes pending delayed actions' do
      workflow = create(:escalated_workflow, trigger_event: 'ticket.created',
                                             conditions: { 'all' => [] }, actions: [])
      create(:escalated_delayed_action,
             workflow: workflow, ticket: ticket,
             action_data: { 'type' => 'change_priority', 'value' => 'urgent' },
             execute_at: 1.minute.ago)

      engine.process_delayed_actions
      ticket.reload
      expect(ticket.priority).to eq('urgent')
    end
  end
end
