# frozen_string_literal: true

module Escalated
  module NewsletterAccess
    extend ActiveSupport::Concern

    private

    def ensure_newsletters_enabled!
      return if Escalated.configuration.enable_newsletters?

      head :not_found
    end

    def require_newsletter_permission!(slug)
      return if newsletter_permission_granted?(slug)

      render_page 'Escalated/Error', {
        status: 403,
        message: I18n.t('escalated.middleware.not_authorized')
      }, status: :forbidden
    end

    def require_newsletter_send_permission!
      require_newsletter_permission!('newsletters.send')
    end

    def newsletter_permission_granted?(slug)
      user = escalated_current_user
      return false unless user

      return true if user.respond_to?(:has_permission?) && user.has_permission?(slug)

      roles = newsletter_roles_for(user)
      return true if roles.nil? && current_user_data&.dig(:is_admin)
      return false if roles.blank?

      roles.any? do |role|
        role.respond_to?(:has_permission?) && role.has_permission?(slug)
      end
    end

    def newsletter_roles_for(user)
      if user.respond_to?(:escalated_roles)
        user.escalated_roles
      elsif user.respond_to?(:roles)
        user.roles
      end
    end
  end
end
