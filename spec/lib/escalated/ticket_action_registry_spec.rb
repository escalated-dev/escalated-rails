# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::TicketActionRegistry do
  let(:ticket) { Struct.new(:id, :reference).new(1, 'TK-1') }
  let(:user) { Struct.new(:id).new(9) }

  describe '.from_config' do
    it 'registers actions and finds them by key' do
      registry = described_class.from_config([{ key: 'sync-crm', label: 'Sync CRM' }])

      expect(registry.find('sync-crm')).to be_present
      expect(registry.find('missing')).to be_nil
    end
  end

  describe '#for_ticket' do
    it 'serializes a config action with sensible defaults' do
      registry = described_class.from_config([{ key: 'sync-crm', label: 'Sync CRM' }])

      expect(registry.for_ticket(ticket, user)).to eq(
        [
          {
            key: 'sync-crm',
            label: 'Sync CRM',
            variant: 'secondary',
            confirmation: nil,
            disabled: false,
            metadata: {}
          }
        ]
      )
    end

    it 'omits invisible actions and marks disabled ones' do
      registry = described_class.from_config(
        [
          { key: 'hidden', label: 'Hidden', visible: false },
          { key: 'locked', label: 'Locked', enabled: false }
        ]
      )

      actions = registry.for_ticket(ticket, user)
      expect(actions.pluck(:key)).to eq(['locked'])
      expect(actions.first[:disabled]).to be(true)
    end

    it 'resolves callable fields with ticket and user' do
      registry = described_class.from_config(
        [
          {
            key: 'dyn',
            label: ->(t, _u) { "Sync #{t.reference}" },
            visible: ->(_t, u) { u.id == 9 },
            metadata: ->(_t, _u) { { icon: 'refresh-cw' } }
          }
        ]
      )

      action = registry.for_ticket(ticket, user).first
      expect(action[:label]).to eq('Sync TK-1')
      expect(action[:metadata]).to eq({ icon: 'refresh-cw' })
      expect(registry.for_ticket(ticket, Struct.new(:id).new(1))).to be_empty
    end
  end

  describe '#register' do
    it 'raises when key or label is missing' do
      expect { described_class.new.register({ key: 'x' }) }.to raise_error(ArgumentError)
    end
  end
end
