# frozen_string_literal: true

require 'rails_helper'

# ctx.store.query from a plugin, run against whichever database the suite is
# on. The filter and ordering were written as MySQL's JSON_UNQUOTE(JSON_EXTRACT())
# and failed outright on SQLite and PostgreSQL.
RSpec.describe Escalated::Bridge::ContextHandler, '#call' do
  subject(:handler) { described_class.new }

  before do
    [
      { 'key' => 'a', 'status' => 'open', 'priority' => 2, 'vip' => true, 'owner' => { 'team' => 'red' } },
      { 'key' => 'b', 'status' => 'open', 'priority' => 10, 'vip' => false, 'owner' => { 'team' => 'blue' } },
      { 'key' => 'c', 'status' => 'closed', 'priority' => 5, 'vip' => true, 'owner' => { 'team' => 'red' } }
    ].each do |data|
      Escalated::PluginStoreRecord.create!(plugin: 'crm', collection: 'deals', key: data['key'], data: data)
    end

    Escalated::PluginStoreRecord.create!(plugin: 'other', collection: 'deals', key: 'z',
                                         data: { 'key' => 'z', 'status' => 'open', 'priority' => 1 })
  end

  def keys(filter = {}, options = {})
    handler.call('ctx.store.query',
                 { 'plugin' => 'crm', 'collection' => 'deals', 'filter' => filter, 'options' => options })
           .map { |record| record['key'] }
  end

  it 'filters on a string field' do
    expect(keys('status' => 'open')).to contain_exactly('a', 'b')
  end

  it 'filters on a number, a boolean and a nested field' do
    expect(keys('priority' => 10)).to eq(['b'])
    expect(keys('vip' => true)).to contain_exactly('a', 'c')
    expect(keys('owner.team' => 'red')).to contain_exactly('a', 'c')
  end

  it 'compares numbers as numbers' do
    expect(keys('priority' => { '$gt' => 3 })).to contain_exactly('b', 'c')
    expect(keys('priority' => { '$lte' => 5 })).to contain_exactly('a', 'c')
  end

  it 'applies $ne and $in' do
    expect(keys('status' => { '$ne' => 'open' })).to eq(['c'])
    expect(keys('status' => { '$in' => %w[closed] })).to eq(['c'])
    expect(keys('priority' => { '$nin' => [2, 5] })).to eq(['b'])
  end

  it 'orders by a field, numerically' do
    expect(keys({}, { 'orderBy' => 'priority', 'order' => 'desc' })).to eq(%w[b c a])
    expect(keys({ 'status' => 'open' }, { 'orderBy' => 'priority' })).to eq(%w[a b])
  end

  it 'refuses a field name that is not a plain dotted path' do
    expect { keys("status') = 'x' OR ('1' = '1" => 'open') }.to raise_error(ArgumentError)
    expect { keys({}, { 'orderBy' => 'priority); DROP TABLE escalated_plugin_store; --' }) }
      .to raise_error(ArgumentError)
  end
end
