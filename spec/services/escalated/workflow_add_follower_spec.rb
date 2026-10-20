# frozen_string_literal: true

require 'rails_helper'

# The add_follower action ran `value.to_i`, so on a host with UUID or string
# user keys the follower became user 0 (or the lookup failed).
RSpec.describe Escalated::WorkflowEngine do
  it 'passes the add_follower user key through unchanged' do
    ticket = create(:escalated_ticket)
    workflow = create(:escalated_workflow)
    allow(ticket).to receive(:follow)

    described_class.new.send(:execute_single_action,
                             { 'type' => 'add_follower', 'value' => '9b2f0c4e-uuid-user' }, ticket, workflow)

    expect(ticket).to have_received(:follow).with('9b2f0c4e-uuid-user')
  end
end
