# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Newsletter::ContactSegmentResolver do
  subject(:resolver) { described_class.new }

  before do
    create(:escalated_contact, email: 'a@example.com')
    create(:escalated_contact, email: 'b@example.com')
  end

  it 'matches an allowlisted field/operator rule' do
    filter = { 'rules' => [{ 'field' => 'email', 'op' => '=', 'value' => 'a@example.com' }] }
    expect(resolver.count_matches(filter)).to eq(1)
  end

  # Regression: field/op came from saved filter JSON and were interpolated raw
  # into SQL. A non-column field must be skipped, never executed.
  it 'skips a rule whose field is not a real column (SQL-injection guard)' do
    filter = { 'rules' => [{ 'field' => 'id); DROP TABLE escalated_contacts; --', 'op' => '=', 'value' => 1 }] }

    expect { resolver.count_matches(filter) }.not_to raise_error
    expect(resolver.count_matches(filter)).to eq(2) # rule ignored -> all contacts
    expect(Escalated::Contact.count).to eq(2)       # table intact
  end

  it 'skips a rule whose operator is not allowlisted' do
    filter = { 'rules' => [{ 'field' => 'id', 'op' => '> 0 OR 1=1; --', 'value' => 0 }] }

    expect { resolver.count_matches(filter) }.not_to raise_error
    expect(resolver.count_matches(filter)).to eq(2)
  end

  # metadata is a json column. The rule used to be `metadata LIKE ?`, which
  # PostgreSQL refuses for json and which ignored the operator everywhere.
  describe 'metadata rules' do
    before do
      create(:escalated_contact, email: 'pro@example.com', metadata: { 'plan' => 'pro', 'seats' => 25 })
      create(:escalated_contact, email: 'team@example.com', metadata: { 'plan' => 'team', 'seats' => 5 })
    end

    it 'matches a metadata value' do
      filter = { 'rules' => [{ 'field' => 'metadata.plan', 'op' => '=', 'value' => 'pro' }] }

      expect(resolver.count_matches(filter)).to eq(1)
    end

    it 'applies the operator to a metadata value' do
      filter = { 'rules' => [{ 'field' => 'metadata.seats', 'op' => '>', 'value' => 10 }] }

      expect(resolver.count_matches(filter)).to eq(1)
    end

    it 'skips a metadata rule whose key is not a plain name' do
      filter = { 'rules' => [{ 'field' => "metadata.plan') = 'pro' OR ('1", 'op' => '=', 'value' => 'x' }] }

      expect { resolver.count_matches(filter) }.not_to raise_error
      expect(resolver.count_matches(filter)).to eq(4)
    end
  end
end
