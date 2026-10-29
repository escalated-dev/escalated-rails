# frozen_string_literal: true

require 'rails_helper'

# The bridge's `cron` and `badge` calls (domain-model/plugin-contract.md).
RSpec.describe Escalated::Bridge::PluginBridge do
  # Stands in for the runtime's JSON-RPC client: records each call and lets
  # the test answer it, calling back into ctx.* like a plugin would.
  let(:rpc_class) do
    Class.new do
      attr_reader :calls

      def initialize(&answer)
        @calls = []
        @answer = answer
      end

      def call(method, params, timeout, handler)
        @calls << [method, params, timeout]
        @answer.call(method, params, handler)
      end
    end
  end

  let(:bridge) { described_class.new }
  let(:user) { create(:user, :agent, name: 'Viewer Vee') }

  def runtime(&answer)
    rpc = rpc_class.new(&answer)
    bridge.instance_variable_set(:@rpc, rpc)
    allow(bridge).to receive(:ensure_alive).and_return(true)
    rpc
  end

  def current_user_outside_a_call
    bridge.instance_variable_get(:@context_handler).call('ctx.currentUser', {})
  end

  it 'asks a badge as the viewer within the filter timeout' do
    rpc = runtime { |_m, _p, handler| "for #{handler.call('ctx.currentUser', {})&.fetch('id')}" }

    expect(bridge.badge('@acme/crm', 'Inbox', user: user)).to eq("for #{user.id}")
    expect(rpc.calls).to eq([['badge', { 'plugin' => '@acme/crm', 'component' => 'Inbox' }, 5]])
    expect(current_user_outside_a_call).to be_nil
  end

  it 'answers numbers and strings, and nil for anything else or a failure' do
    runtime { 7 }
    expect(bridge.badge('@acme/crm', 'Count', user: user)).to eq(7)
    runtime { { 'n' => 1 } }
    expect(bridge.badge('@acme/crm', 'Count', user: user)).to be_nil
    runtime { raise 'badge failed' }
    expect(bridge.badge('@acme/crm', 'Count', user: user)).to be_nil
    expect(current_user_outside_a_call).to be_nil
  end

  it 'runs a cron schedule as no user within the action timeout, logging a failure' do
    seen = []
    rpc = runtime { |_m, _p, handler| seen << handler.call('ctx.currentUser', {}) }
    expect(bridge.cron('@acme/crm', '* * * * *')).to be(true)
    expect(rpc.calls).to eq([['cron', { 'plugin' => '@acme/crm', 'schedule' => '* * * * *' }, 30]])
    expect(seen).to eq([nil])

    runtime { raise 'cron failed' }
    expect(bridge.cron('@acme/crm', '* * * * *')).to be(false)
  end
end
