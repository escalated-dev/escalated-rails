# frozen_string_literal: true

require 'rails_helper'

# HookRegistry documents these action hooks for Ruby plugins, and the engine
# forwards every registry hook to the Node plugin runtime. Nothing fired them:
# do_action ran only for plugin lifecycle and import events.
RSpec.describe 'Ticket lifecycle hooks' do # rubocop:disable RSpec/DescribeClass
  let(:requester) { create(:user) }
  let(:agent) { create(:user, :agent) }
  let(:calls) { [] }
  let(:callbacks) { {} }

  before do
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)

    %w[ticket_before_create ticket_created ticket_updated ticket_status_changed ticket_assigned ticket_closed
       ticket_reopened reply_added ticket_priority_changed ticket_department_changed].each do |hook|
      callbacks[hook] = ->(*args) { calls << [hook, *args] }
      Escalated.hooks.add_action(hook, callbacks[hook])
    end
  end

  after do
    callbacks.each { |hook, callback| Escalated.hooks.remove_action(hook, callback) }
  end

  def fired(hook)
    calls.select { |name, *| name == hook }.map { |_, *args| args }
  end

  it 'fires ticket_before_create with the params and ticket_created with the ticket' do
    ticket = Escalated::Services::TicketService.create(subject: 'Printer on fire', description: 'Smoke.',
                                                       requester: requester)

    expect(fired('ticket_before_create').sole.first).to include(subject: 'Printer on fire')
    expect(fired('ticket_created')).to eq([[ticket]])
  end

  it 'fires ticket_updated with the actor' do
    ticket = create(:escalated_ticket, requester: requester)

    Escalated::Services::TicketService.update(ticket, { subject: 'Printer still on fire' }, actor: agent)

    expect(fired('ticket_updated')).to eq([[ticket, agent]])
  end

  it 'fires ticket_status_changed with the old and new status, and ticket_closed' do
    ticket = create(:escalated_ticket, requester: requester, status: :open)

    Escalated::Services::TicketService.close(ticket, actor: agent)

    expect(fired('ticket_status_changed')).to eq([[ticket, 'open', 'closed', agent]])
    expect(fired('ticket_closed')).to eq([[ticket, agent]])
    expect(fired('ticket_reopened')).to be_empty
  end

  it 'fires ticket_reopened' do
    ticket = create(:escalated_ticket, requester: requester, status: :closed)

    Escalated::Services::TicketService.reopen(ticket, actor: agent)

    expect(fired('ticket_reopened')).to eq([[ticket, agent]])
  end

  it 'fires ticket_assigned with the agent' do
    ticket = create(:escalated_ticket, requester: requester)

    Escalated::Services::TicketService.assign(ticket, agent, actor: agent)

    expect(fired('ticket_assigned')).to eq([[ticket, agent]])
  end

  it 'fires reply_added with the reply' do
    ticket = create(:escalated_ticket, requester: requester)

    reply = Escalated::Services::TicketService.reply(ticket, body: 'On it.', author: agent, is_internal: false)

    expect(fired('reply_added')).to eq([[ticket, reply]])
  end

  it 'fires ticket_priority_changed with the old and new priority' do
    ticket = create(:escalated_ticket, requester: requester, priority: :low)

    Escalated::Services::TicketService.change_priority(ticket, :high, actor: agent)

    expect(fired('ticket_priority_changed')).to eq([[ticket, 'low', 'high', agent]])
  end

  it 'fires ticket_department_changed with the old and new department' do
    billing = create(:escalated_department)
    support = create(:escalated_department)
    ticket = create(:escalated_ticket, requester: requester, department: billing)

    Escalated::Services::TicketService.change_department(ticket, support, actor: agent)

    expect(fired('ticket_department_changed')).to eq([[ticket, billing, support, agent]])
  end

  it 'still creates the ticket when a hook raises' do
    failing = ->(*) { raise 'plugin bug' }
    Escalated.hooks.add_action('ticket_created', failing)

    expect do
      Escalated::Services::TicketService.create(subject: 'Printer on fire', description: 'Smoke.', requester: requester)
    end.to change(Escalated::Ticket, :count).by(1)
  ensure
    Escalated.hooks.remove_action('ticket_created', failing)
  end

  describe 'forwarding to the plugin runtime' do
    around do |example|
      original = Escalated.hooks
      Escalated.instance_variable_set(:@hooks, Escalated::Support::HookManager.new)
      Escalated::Engine.instance_variable_set(:@bridge_hooks_registered, false)
      Escalated::Engine.register_bridge_hooks
      example.run
    ensure
      Escalated.instance_variable_set(:@hooks, original)
      Escalated::Engine.instance_variable_set(:@bridge_hooks_registered, true)
    end

    it 'sends ticket_created to a booted runtime' do
      bridge = instance_double(Escalated::Bridge::PluginBridge, booted?: true)
      allow(Escalated).to receive(:plugin_bridge).and_return(bridge)
      allow(bridge).to receive(:dispatch_action)

      ticket = Escalated::Services::TicketService.create(subject: 'Printer on fire', description: 'Smoke.',
                                                         requester: requester)

      expect(bridge).to have_received(:dispatch_action).with('ticket_created', { 'args' => [ticket.as_json] })
    end
  end
end
