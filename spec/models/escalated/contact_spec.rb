# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::Contact, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:tickets).class_name('Escalated::Ticket').dependent(:nullify) }
  end

  describe 'validations' do
    subject { build(:escalated_contact) }

    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
  end

  describe 'before_validation normalize_email' do
    it 'lowercases and trims whitespace' do
      c = described_class.create!(email: '  UPPER@Case.COM ', metadata: {})
      expect(c.email).to eq('upper@case.com')
    end
  end

  describe '.find_or_create_by_email' do
    it 'creates a new contact for a never-seen email' do
      c = described_class.find_or_create_by_email('new@user.com', 'New User')
      expect(c.email).to eq('new@user.com')
      expect(c.name).to eq('New User')
    end

    it 'normalizes case + whitespace on create' do
      c = described_class.find_or_create_by_email('  MIX@Case.COM ')
      expect(c.email).to eq('mix@case.com')
    end

    it 'returns the existing contact for a repeat email' do
      first = described_class.find_or_create_by_email('alice@example.com', 'Alice')
      second = described_class.find_or_create_by_email('ALICE@example.com')
      expect(second.id).to eq(first.id)
    end

    it 'fills in a blank name on an existing contact when one is provided' do
      create(:escalated_contact, email: 'alice@example.com', name: nil)
      result = described_class.find_or_create_by_email('alice@example.com', 'Alice')
      expect(result.name).to eq('Alice')
    end

    it 'does not overwrite a non-blank existing name' do
      create(:escalated_contact, email: 'alice@example.com', name: 'Alice')
      result = described_class.find_or_create_by_email('alice@example.com', 'Different')
      expect(result.name).to eq('Alice')
    end
  end

  describe '#link_to_user!' do
    it 'sets user_id on the contact' do
      c = create(:escalated_contact, user_id: nil)
      c.link_to_user!(555)
      expect(c.reload.user_id).to eq(555)
    end
  end

  describe '#promote_to_user!' do
    it 'links contact and back-stamps requester_id on prior tickets' do
      contact = create(:escalated_contact, user_id: nil)
      t1 = create(:escalated_ticket, contact: contact, requester: nil)
      t2 = create(:escalated_ticket, contact: contact, requester: nil)

      contact.promote_to_user!(555, 'User')

      expect(contact.reload.user_id).to eq(555)
      expect(t1.reload.requester_id).to eq(555)
      expect(t1.requester_type).to eq('User')
      expect(t2.reload.requester_id).to eq(555)
    end
  end

  describe 'tickets association' do
    it 'has_many tickets via contact_id' do
      contact = create(:escalated_contact)
      t1 = create(:escalated_ticket, contact: contact, requester: nil)
      t2 = create(:escalated_ticket, contact: contact, requester: nil)
      # Unrelated ticket
      create(:escalated_ticket, requester: nil)

      expect(contact.tickets.map(&:id)).to contain_exactly(t1.id, t2.id)
    end
  end

  describe 'repeat-submission dedupe (Pattern B)' do
    it 'yields one Contact row even when find_or_create_by_email is called with different casing / whitespace' do
      c1 = described_class.find_or_create_by_email('alice@example.com', 'Alice')
      c2 = described_class.find_or_create_by_email('  ALICE@Example.COM  ', 'Alice')
      c3 = described_class.find_or_create_by_email('alice@example.com', 'Different')

      expect(c1.id).to eq(c2.id)
      expect(c2.id).to eq(c3.id)
      expect(described_class.where(email: 'alice@example.com').count).to eq(1)
    end
  end
end
