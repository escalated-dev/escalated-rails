# frozen_string_literal: true

require 'rails_helper'

# The suite runs on the adapter it was told to run on.
#
# A CI matrix leg that quietly fell back to SQLite would go green having tested
# nothing the matrix exists to test, and the failure mode is invisible: every
# other example still passes. This is the one spec that notices.
RSpec.describe 'the database the suite runs against', type: :model do
  let(:requested) { ENV.fetch('ESCALATED_TEST_ADAPTER', 'sqlite3') }

  it 'connects to the adapter the environment asked for' do
    expected = {
      'sqlite3' => 'SQLite',
      'postgresql' => 'PostgreSQL',
      'mysql2' => 'Mysql2'
    }.fetch(requested)

    expect(ActiveRecord::Base.connection.adapter_name).to eq(expected),
                                                          "asked for #{requested}, connected to " \
                                                          "#{ActiveRecord::Base.connection.adapter_name}"
  end

  it 'reaches a database it can actually query' do
    # adapter_name reads configuration, not a socket. Without this, a leg
    # pointed at a database that never came up would still pass the check above.
    expect(ActiveRecord::Base.connection.select_value('SELECT 1').to_i).to eq(1)
  end

  it 'has the engine tables on that database' do
    expect(ActiveRecord::Base.connection.table_exists?('escalated_tickets')).to be(true)
  end
end
