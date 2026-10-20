# frozen_string_literal: true

require 'rails_helper'
require File.expand_path('../../db/migrate/064_change_escalated_agent_columns_to_user_id_type', __dir__)

# department_agents.agent_id and chat_sessions.agent_id were bigint while every
# other host-user column follows Escalated.user_id_type, so department
# membership, department visibility and chat assignment failed on UUID hosts.
#
# The DDL itself is stubbed: MySQL commits implicitly on it, which would end the
# example's transaction.
RSpec.describe ChangeEscalatedAgentColumnsToUserIdType do
  let(:migration) { described_class.new }

  let(:calls) { [] }

  before do
    allow(migration).to receive(:change_column) { |*args, **opts| calls << [*args, opts] }
  end

  it 'changes nothing on a bigint host' do
    allow(Escalated).to receive(:user_id_type).and_return(:bigint)

    migration.up

    expect(calls).to be_empty
  end

  %i[uuid string].each do |type|
    it "moves both agent columns to #{type} on a #{type} host, keeping their nullability" do
      allow(Escalated).to receive(:user_id_type).and_return(type)

      migration.up

      expect(calls.map { |table, column, t, opts| [table, column, t, opts[:null]] }).to eq(
        [
          [Escalated.table_name('department_agents'), 'agent_id', type, false],
          [Escalated.table_name('chat_sessions'), 'agent_id', type, true]
        ]
      )
    end
  end
end
