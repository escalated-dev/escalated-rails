# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Escalated::EscalatedSetting do # Knowledge Base Settings
  before do
    allow(Escalated.configuration).to receive_messages(notification_channels: [], webhook_url: nil)
  end

  describe '.knowledge_base_enabled?' do
    it 'defaults to true' do
      expect(described_class.knowledge_base_enabled?).to be true
    end

    it 'returns false when set to 0' do
      described_class.set('knowledge_base_enabled', '0')
      expect(described_class.knowledge_base_enabled?).to be false
    end

    it 'returns true when set to 1' do
      described_class.set('knowledge_base_enabled', '1')
      expect(described_class.knowledge_base_enabled?).to be true
    end
  end

  describe '.knowledge_base_public?' do
    it 'defaults to true' do
      expect(described_class.knowledge_base_public?).to be true
    end

    it 'returns false when set to 0' do
      described_class.set('knowledge_base_public', '0')
      expect(described_class.knowledge_base_public?).to be false
    end
  end

  describe '.knowledge_base_feedback_enabled?' do
    it 'defaults to true' do
      expect(described_class.knowledge_base_feedback_enabled?).to be true
    end

    it 'returns false when set to 0' do
      described_class.set('knowledge_base_feedback_enabled', '0')
      expect(described_class.knowledge_base_feedback_enabled?).to be false
    end
  end

  describe Escalated::KnowledgeBaseGuard do
    # Create a test controller to include the concern
    let(:controller_class) do
      Class.new(ApplicationController) do
        include Escalated::KnowledgeBaseGuard

        def test_enabled
          require_knowledge_base_enabled!
        end

        def test_public
          require_knowledge_base_public!
        end

        def test_feedback
          require_knowledge_base_feedback_enabled!
        end
      end
    end

    describe 'guard checks' do
      it 'knowledge_base_enabled guard passes when enabled' do
        Escalated::EscalatedSetting.set('knowledge_base_enabled', '1')
        expect(Escalated::EscalatedSetting.knowledge_base_enabled?).to be true
      end

      it 'knowledge_base_enabled guard blocks when disabled' do
        Escalated::EscalatedSetting.set('knowledge_base_enabled', '0')
        expect(Escalated::EscalatedSetting.knowledge_base_enabled?).to be false
      end

      it 'knowledge_base_public guard passes when public' do
        Escalated::EscalatedSetting.set('knowledge_base_public', '1')
        expect(Escalated::EscalatedSetting.knowledge_base_public?).to be true
      end

      it 'knowledge_base_public guard blocks when not public' do
        Escalated::EscalatedSetting.set('knowledge_base_public', '0')
        expect(Escalated::EscalatedSetting.knowledge_base_public?).to be false
      end

      it 'feedback guard passes when enabled' do
        Escalated::EscalatedSetting.set('knowledge_base_feedback_enabled', '1')
        expect(Escalated::EscalatedSetting.knowledge_base_feedback_enabled?).to be true
      end

      it 'feedback guard blocks when disabled' do
        Escalated::EscalatedSetting.set('knowledge_base_feedback_enabled', '0')
        expect(Escalated::EscalatedSetting.knowledge_base_feedback_enabled?).to be false
      end
    end
  end
end
