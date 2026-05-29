# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated do
  describe '.user_id_type' do
    around do |example|
      original = described_class.configuration.user_id_type
      example.run
      described_class.configuration.user_id_type = original
    end

    it 'defaults to :bigint when config is :auto and the user model has an integer PK' do
      described_class.configuration.user_id_type = :auto
      expect(described_class.user_id_type).to eq(:bigint)
    end

    it 'returns :uuid when configured' do
      described_class.configuration.user_id_type = :uuid
      expect(described_class.user_id_type).to eq(:uuid)
    end
  end
end
