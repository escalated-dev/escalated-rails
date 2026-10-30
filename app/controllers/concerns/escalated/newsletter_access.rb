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

    # While roles & permissions is off the admin gate (already passed)
    # decides, like every other admin screen. While it is on, the user's
    # Escalated roles must grant the newsletter permission.
    def newsletter_permission_granted?(slug)
      user = escalated_current_user
      return false unless user

      Escalated::AccessControl.allows?(user.id, slug)
    end
  end
end
