# frozen_string_literal: true

require 'rails_helper'

# Ensure the app/services autoloader has warmed up the constant.

RSpec.describe Escalated::Services::WorkflowSubscriber do
  let(:ticket) { create(:escalated_ticket) }

  before do
    # Subscribe once (idempotent in the subscriber itself).
    described_class.subscribe!
  end

  def instrument(event_name, payload)
    ActiveSupport::Notifications.instrument("escalated.notification.#{event_name}", payload)
  end

  it 'invokes WorkflowEngine#process_event with the right trigger on ticket_created' do
    engine = instance_double(Escalated::WorkflowEngine)
    allow(Escalated::WorkflowEngine).to receive(:new).and_return(engine)
    expect(engine).to receive(:process_event).with('ticket.created', ticket, {})

    instrument(:ticket_created, ticket: ticket)
  end

  it 'maps status_changed to ticket.status_changed, and a resolve to ticket.resolved as well' do
    engine = instance_double(Escalated::WorkflowEngine)
    allow(Escalated::WorkflowEngine).to receive(:new).and_return(engine)
    expect(engine).to receive(:process_event).with('ticket.status_changed', ticket, { status: :resolved }).ordered
    expect(engine).to receive(:process_event).with('ticket.resolved', ticket, { status: :resolved }).ordered

    instrument(:status_changed, ticket: ticket, status: :resolved)
  end

  it 'maps a public reply to reply.created and an internal note to note.created' do
    engine = instance_double(Escalated::WorkflowEngine)
    allow(Escalated::WorkflowEngine).to receive(:new).and_return(engine)
    public_reply = build(:escalated_reply, ticket: ticket, is_internal: false)
    note = build(:escalated_reply, ticket: ticket, is_internal: true)
    expect(engine).to receive(:process_event).with('reply.created', ticket, { reply: public_reply }).ordered
    expect(engine).to receive(:process_event).with('note.created', ticket, { reply: note }).ordered

    instrument(:reply_added, ticket: ticket, reply: public_reply)
    instrument(:reply_added, ticket: ticket, reply: note)
  end

  it 'fires nothing for a notification with no canonical name' do
    engine = instance_double(Escalated::WorkflowEngine)
    allow(Escalated::WorkflowEngine).to receive(:new).and_return(engine)
    expect(engine).not_to receive(:process_event)

    instrument(:ticket_snoozed, ticket: ticket)
  end

  it 'is a no-op when payload has no ticket' do
    engine = instance_double(Escalated::WorkflowEngine)
    allow(Escalated::WorkflowEngine).to receive(:new).and_return(engine)
    expect(engine).not_to receive(:process_event)

    instrument(:ticket_created, { reason: 'no ticket here' })
  end

  it 'swallows engine errors (logs a warning instead of crashing the caller)' do
    engine = instance_double(Escalated::WorkflowEngine)
    allow(Escalated::WorkflowEngine).to receive(:new).and_return(engine)
    allow(engine).to receive(:process_event).and_raise(StandardError, 'boom')
    allow(Rails.logger).to receive(:warn)

    expect do
      instrument(:ticket_created, ticket: ticket)
    end.not_to raise_error
    expect(Rails.logger).to have_received(:warn).with(/ticket\.created failed.*boom/)
  end

  it 'is idempotent — calling subscribe! twice does not double-fire' do
    described_class.subscribe!
    described_class.subscribe!

    engine = instance_double(Escalated::WorkflowEngine)
    allow(Escalated::WorkflowEngine).to receive(:new).and_return(engine)
    expect(engine).to receive(:process_event).once

    instrument(:ticket_created, ticket: ticket)
  end
end
