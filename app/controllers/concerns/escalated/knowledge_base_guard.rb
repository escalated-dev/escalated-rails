# frozen_string_literal: true

module Escalated
  module KnowledgeBaseGuard
    extend ActiveSupport::Concern

    private

    def require_knowledge_base_enabled!
      return if Escalated::EscalatedSetting.knowledge_base_enabled?

      render json: { error: 'Knowledge base is disabled' }, status: :forbidden
    end

    def require_knowledge_base_public!
      return if Escalated::EscalatedSetting.knowledge_base_public?

      render json: { error: 'Knowledge base is not publicly accessible' }, status: :forbidden
    end

    def require_knowledge_base_feedback_enabled!
      return if Escalated::EscalatedSetting.knowledge_base_feedback_enabled?

      render json: { error: 'Knowledge base feedback is disabled' }, status: :forbidden
    end
  end
end
