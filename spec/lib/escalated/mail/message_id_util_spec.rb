# frozen_string_literal: true

require 'rails_helper'
require 'escalated/mail/message_id_util'

RSpec.describe Escalated::Mail::MessageIdUtil do
  let(:domain) { 'support.example.com' }
  let(:secret) { 'test-secret-long-enough-for-hmac' }

  describe '.build_message_id' do
    it 'uses the ticket form for nil reply_id' do
      expect(described_class.build_message_id(42, nil, domain))
        .to eq('<ticket-42@support.example.com>')
    end

    it 'appends the -reply-{id} tail when reply_id is non-nil' do
      expect(described_class.build_message_id(42, 7, domain))
        .to eq('<ticket-42-reply-7@support.example.com>')
    end
  end

  describe '.parse_ticket_id_from_message_id' do
    it 'round-trips a built initial id' do
      id = described_class.build_message_id(42, nil, domain)
      expect(described_class.parse_ticket_id_from_message_id(id)).to eq(42)
    end

    it 'round-trips a built reply id' do
      id = described_class.build_message_id(42, 7, domain)
      expect(described_class.parse_ticket_id_from_message_id(id)).to eq(42)
    end

    it 'accepts values without angle brackets' do
      expect(described_class.parse_ticket_id_from_message_id('ticket-99@example.com'))
        .to eq(99)
    end

    it 'returns nil for nil input' do
      expect(described_class.parse_ticket_id_from_message_id(nil)).to be_nil
    end

    it 'returns nil for empty string' do
      expect(described_class.parse_ticket_id_from_message_id('')).to be_nil
    end

    it 'returns nil for unrelated input' do
      expect(described_class.parse_ticket_id_from_message_id('<random@mail.com>')).to be_nil
    end

    it 'returns nil for non-numeric ticket id' do
      expect(described_class.parse_ticket_id_from_message_id('ticket-abc@example.com')).to be_nil
    end
  end

  describe '.build_reply_to' do
    it 'is stable for the same inputs' do
      first = described_class.build_reply_to(42, secret, domain)
      again = described_class.build_reply_to(42, secret, domain)
      expect(first).to eq(again)
      expect(first).to match(/\Areply\+42\.[a-f0-9]{8}@support\.example\.com\z/)
    end

    it 'produces different signatures for different tickets' do
      a = described_class.build_reply_to(42, secret, domain)
      b = described_class.build_reply_to(43, secret, domain)
      expect(a.split('@').first).not_to eq(b.split('@').first)
    end
  end

  describe '.verify_reply_to' do
    it 'round-trips a built address' do
      address = described_class.build_reply_to(42, secret, domain)
      expect(described_class.verify_reply_to(address, secret)).to eq(42)
    end

    it 'accepts the local part only' do
      address = described_class.build_reply_to(42, secret, domain)
      local = address.split('@').first
      expect(described_class.verify_reply_to(local, secret)).to eq(42)
    end

    it 'rejects a tampered signature' do
      address = described_class.build_reply_to(42, secret, domain)
      at = address.index('@')
      local = address[0..(at - 1)]
      last = local[-1]
      tampered = local[0..-2] + (last == '0' ? '1' : '0') + address[at..]
      expect(described_class.verify_reply_to(tampered, secret)).to be_nil
    end

    it 'rejects a wrong secret' do
      address = described_class.build_reply_to(42, secret, domain)
      expect(described_class.verify_reply_to(address, 'different-secret')).to be_nil
    end

    it 'rejects malformed input' do
      expect(described_class.verify_reply_to(nil, secret)).to be_nil
      expect(described_class.verify_reply_to('', secret)).to be_nil
      expect(described_class.verify_reply_to('alice@example.com', secret)).to be_nil
      expect(described_class.verify_reply_to('reply@example.com', secret)).to be_nil
      expect(described_class.verify_reply_to('reply+abc.deadbeef@example.com', secret)).to be_nil
    end

    it 'is case-insensitive on the hex signature' do
      address = described_class.build_reply_to(42, secret, domain)
      expect(described_class.verify_reply_to(address.upcase, secret)).to eq(42)
    end
  end
end
