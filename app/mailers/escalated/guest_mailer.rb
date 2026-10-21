# frozen_string_literal: true

module Escalated
  class GuestMailer < ApplicationMailer
    # The only place the code ever appears.
    def verification_code(email, code)
      @code = code
      mail(to: email, subject: I18n.t('escalated.guest_verification.subject', default: 'Your verification code'))
    end
  end
end
