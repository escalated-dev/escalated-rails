# frozen_string_literal: true

module Escalated
  module Support
    # Remembers, per session, which user passed the two-factor challenge. The
    # user's id is stored, so a session that passed for one user does not count
    # for another, and the mark is cleared on every login and logout (a Warden
    # hook when Warden is present; hosts on other auth call `forget`).
    module TwoFactorSession
      KEY = 'escalated.two_factor.passed'
      INTENDED = 'escalated.two_factor.intended'

      module_function

      def passed?(session, user)
        session.present? && user.present? && session[KEY] == user.id.to_s
      end

      def mark_passed(session, user)
        session[KEY] = user.id.to_s
      end

      def forget(session)
        session&.delete(KEY)
      end

      def remember_intended(session, url)
        session[INTENDED] = url
      end

      def take_intended(session)
        url = session&.delete(INTENDED)
        url.is_a?(String) && url.start_with?('/') && !url.start_with?('//') ? url : nil
      end
    end
  end
end
