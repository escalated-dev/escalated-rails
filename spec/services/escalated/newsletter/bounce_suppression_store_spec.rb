# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Newsletter::BounceSuppressionStore do
  subject(:store) { described_class.new }

  it 'marks bounced and complained emails case-insensitively' do
    store.mark_bounced('User@Example.com')
    store.mark_complained('Other@Example.com')

    expect(store.bounced?('user@example.com')).to be true
    expect(store.bounced?('OTHER@example.com')).to be true
  end

  it 'filters sendable emails against the persisted suppression list' do
    store.mark_bounced('blocked@example.com')

    expect(store.filter_sendable(%w[ok@example.com BLOCKED@example.com])).to eq(['ok@example.com'])
  end
end
