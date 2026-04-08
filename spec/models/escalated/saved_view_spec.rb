# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::SavedView do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  before do
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)
  end

  describe 'validations' do
    it 'requires a name' do
      view = build(:escalated_saved_view, name: nil)
      expect(view).not_to be_valid
      expect(view.errors[:name]).to include("can't be blank")
    end

    it 'limits name to 100 characters' do
      view = build(:escalated_saved_view, name: 'a' * 101)
      expect(view).not_to be_valid
    end

    it 'is valid with valid attributes' do
      view = build(:escalated_saved_view)
      expect(view).to be_valid
    end
  end

  describe 'scopes' do
    let!(:user_view) { create(:escalated_saved_view, user: user) }
    let!(:shared_view) { create(:escalated_saved_view, :shared, user: other_user) }
    let!(:other_view) { create(:escalated_saved_view, user: other_user, is_shared: false) }
    let!(:default_view) { create(:escalated_saved_view, :default_view, user: user) }

    describe '.for_user' do
      it 'returns views belonging to the user' do
        result = described_class.for_user(user.id)
        expect(result).to include(user_view, default_view)
        expect(result).not_to include(shared_view, other_view)
      end
    end

    describe '.shared' do
      it 'returns only shared views' do
        result = described_class.shared
        expect(result).to include(shared_view)
        expect(result).not_to include(user_view, other_view)
      end
    end

    describe '.default_views' do
      it 'returns default views' do
        result = described_class.default_views
        expect(result).to include(default_view)
        expect(result).not_to include(user_view)
      end
    end

    describe '.accessible_by' do
      it 'returns user views and shared views' do
        result = described_class.accessible_by(user.id)
        expect(result).to include(user_view, shared_view, default_view)
        expect(result).not_to include(other_view)
      end
    end

    describe '.ordered' do
      it 'orders by position then name' do
        view_a = create(:escalated_saved_view, user: user, position: 1, name: 'B View')
        view_b = create(:escalated_saved_view, user: user, position: 0, name: 'A View')
        result = described_class.for_user(user.id).ordered
        positions = result.pluck(:position)
        expect(positions).to eq(positions.sort)
      end
    end
  end

  describe 'filters' do
    it 'stores and retrieves JSON filters' do
      filters = { 'status' => 'open', 'priority' => 'high', 'tags' => [1, 2] }
      view = create(:escalated_saved_view, user: user, filters: filters)
      view.reload
      expect(view.filters).to eq(filters)
    end
  end
end
